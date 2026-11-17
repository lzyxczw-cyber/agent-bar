/**
 * dsh-auth.mjs — read-only discovery of the running DSH GUI and its auth material.
 *
 * Verified against DSH 0.2.2-rc.3 (desktop app, 2026-11-16):
 *  - The DSH host authenticates its Web GUI with an HMAC-signed browser-session
 *    cookie: name "dsh-auth-<base64url(sha256(authority))>", value
 *    "v1.<base64url(payload)>.<base64url(HMAC-SHA256(secret, body))>".
 *  - The HMAC secret is a durable 32-byte key stored in
 *    $DSH_HOME/.credentials.yaml under
 *    records["client-connection/browser-session"].payload.secret.
 *  - Minting an equivalent cookie for loopback authority 127.0.0.1:<port> is a
 *    read-only operation: no DSH state is modified and no Chromium cookie
 *    decryption is needed. It authenticates both HTTP /api and the Gateway
 *    WebSocket /api/remote.mux as the ordinary owner browser peer.
 *  - The GUI listens on a random loopback port; discovery order is
 *    --url, DSH_WEB_URL (exported into DSH shells), then lsof LISTEN ports.
 *
 * Secrets and cookie values are never logged by this module.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash, createHmac } from 'node:crypto';
import { execFile } from 'node:child_process';

const COOKIE_PREFIX = 'dsh-auth-';
const CREDENTIAL_KEY = 'client-connection/browser-session';

/** Resolve the DSH home directory. */
export function dshHome () {
  return process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
}

/**
 * Parse the browser-session signing secret out of the DSH credentials YAML.
 * The file has a small fixed shape; only the record we need is read.
 */
export function readBrowserSessionSecret (home = dshHome ()) {
  const file = path.join(home, '.credentials.yaml');
  let text;
  try {
    text = fs.readFileSync (file, 'utf8');
  } catch (error) {
    throw new Error ('cannot read DSH credentials store ' + file + ': ' + error.message);
  }
  let inRecord = false;
  let inPayload = false;
  for (const line of text.split ('\n')) {
    if (line === '  ' + CREDENTIAL_KEY + ':') { inRecord = true; inPayload = false; continue; }
    if (inRecord && line.startsWith ('  ') && !line.startsWith ('    ') && line.trim () !== '') {
      inRecord = false; inPayload = false;
      continue;
    }
    if (!inRecord) continue;
    if (line === '    payload:') { inPayload = true; continue; }
    if (inPayload && line.startsWith ('      secret:')) {
      const value = line.slice ('      secret:'.length).trim ();
      const secret = Buffer.from (value, 'base64url');
      if (secret.length !== 32) throw new Error ('DSH browser-session secret has unexpected length ' + secret.length);
      return secret;
    }
    if (inPayload && line.startsWith ('    ') && !line.startsWith ('      ')) inPayload = false;
  }
  throw new Error ('DSH credentials store has no ' + CREDENTIAL_KEY + ' grant; open the DSH desktop app once');
}

function base64url (buffer) {
  return Buffer.from (buffer).toString ('base64').replaceAll ('+', '-').replaceAll ('/', '_').replace (/=+$/u, '');
}

/** Build the exact cookie the DSH host expects for one authority. */
export function mintCookie (secret, authority, { ttlMs = 24 * 60 * 60 * 1000, now = Date.now () } = {}) {
  if (typeof authority !== 'string' || authority === '') throw new TypeError ('authority is required');
  if (!Buffer.isBuffer (secret) || secret.length !== 32) throw new TypeError ('secret must be the 32-byte browser-session key');
  const payload = { version: 1, authority, issuedAt: now, expiresAt: now + ttlMs };
  const body = base64url (JSON.stringify (payload));
  const signature = base64url (createHmac ('sha256', secret).update (body).digest ());
  const name = COOKIE_PREFIX + base64url (createHash ('sha256').update (authority).digest ());
  return { name, value: 'v1.' + body + '.' + signature };
}

/** True when a response body looks like the DSH Web GUI index. */
export function looksLikeDshIndex (body) {
  return typeof body === 'string' && body.slice (0, 200).toLowerCase ().includes ('<!doctype html');
}

/** Probe one candidate origin with the minted cookie. */
export async function probeOrigin (origin, cookie, { timeoutMs = 1200 } = {}) {
  try {
    const response = await fetch (origin + '/', {
      headers: { cookie: cookie.name + '=' + cookie.value },
      signal: AbortSignal.timeout (timeoutMs),
      redirect: 'manual'
    });
    if (response.status !== 200) return false;
    const body = await response.text ();
    return looksLikeDshIndex (body);
  } catch {
    return false;
  }
}

/**
 * List loopback TCP listeners using lsof (present on macOS).
 * Returns [{port, pid, command}], desktop-app ports first.
 */
export async function listLoopbackListeners () {
  const output = await new Promise ((resolve) => {
    execFile ('lsof', ['-nP', '-iTCP', '-sTCP:LISTEN', '-Fpcn'], { timeout: 4000 }, (error, stdout) => {
      resolve (error ? '' : stdout);
    });
  });
  const listeners = [];
  let command = '';
  for (const line of output.split ('\n')) {
    if (line.startsWith ('c')) { command = line.slice (1); continue; }
    if (!line.startsWith ('n')) continue;
    const address = line.slice (1);
    let port = null;
    if (address.startsWith ('127.0.0.1:')) port = Number (address.slice ('127.0.0.1:'.length));
    else if (address.startsWith ('[::1]:')) port = Number (address.slice ('[::1]:'.length));
    if (!port || !Number.isSafeInteger (port)) continue;
    listeners.push ({ port, command });
  }
  const rank = (entry) => (entry.command.toLowerCase ().includes ('deepseek') ? 0 : 1);
  return listeners.sort ((a, b) => rank (a) - rank (b) || a.port - b.port);
}

function normalizeOrigin (value) {
  if (typeof value !== 'string' || value.trim () === '') return null;
  try { return new URL (value.trim ()).origin; } catch { return null; }
}

/**
 * Discover the running DSH GUI origin and return { origin, source, cookie, secret }.
 * Priority: --url, DSH_WEB_URL, lsof loopback listeners (desktop app first).
 */
export async function discoverDsh ({ explicitUrl = null, home = dshHome () } = {}) {
  const secret = readBrowserSessionSecret (home);
  const candidates = [];
  const explicit = normalizeOrigin (explicitUrl);
  if (explicit) candidates.push ({ origin: explicit, source: 'flag' });
  const fromEnv = normalizeOrigin (process.env.DSH_WEB_URL);
  if (fromEnv && fromEnv !== explicit) candidates.push ({ origin: fromEnv, source: 'env' });
  let firstProbeOk = false;
  if (candidates.length > 0) {
    firstProbeOk = await probeOrigin (candidates[0].origin, mintCookie (secret, new URL (candidates[0].origin).host));
  }
  if (!firstProbeOk) {
    for (const listener of await listLoopbackListeners ()) {
      candidates.push ({ origin: 'http://127.0.0.1:' + listener.port, source: 'lsof' });
    }
  }
  const seen = new Set ();
  for (const candidate of candidates) {
    if (seen.has (candidate.origin)) continue;
    seen.add (candidate.origin);
    const cookie = mintCookie (secret, new URL (candidate.origin).host);
    if (await probeOrigin (candidate.origin, cookie)) {
      return { origin: candidate.origin, source: candidate.source, cookie, secret };
    }
  }
  throw new Error ('running DSH Web GUI not found; set DSH_WEB_URL or pass --url (candidates: '
    + (candidates.length === 0 ? 'none' : candidates.map ((item) => item.origin).join (', ')) + ')');
}

/** Re-mint the cookie for a known origin (cheap; used after reconnects). */
export function cookieFor (secret, origin) {
  return mintCookie (secret, new URL (origin).host);
}
