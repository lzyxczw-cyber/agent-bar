/**
 * translate.mjs — optional localization of assistant "thought" text for the
 * Agent Bar bridge.
 *
 * English (or mixed) reasoning strings are translated to Simplified Chinese
 * asynchronously through the DeepSeek chat API and returned as a separate
 * value; the original thinking text is never modified. The API key is read from
 * $DEEPSEEK_API_KEY first, then from $DSH_HOME/.credentials.yaml under
 * refs.DEEPSEEK_API_KEY. The key is only ever placed in the Authorization
 * header: it is never logged, written to disk, or included in an error string.
 *
 * Behaviour encoded here:
 *  - at most one HTTP request in flight, 8 s timeout, >= 8 s per agent gap
 *  - LRU cache of 64 translations keyed by sha256(source text)
 *  - only changed text is translated; empty / already-Chinese text -> null
 *  - failures are silent (throttled status-only log) and fall back to null
 *  - a failed text is retried no more often than every 60 s
 *
 * The bridge main tick only *schedules* work (observe); snapshots read the
 * cached result (thoughtZhFor). --once uses drain() to wait for completion.
 */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { dshHome } from './dsh-auth.mjs';

const API_URL = 'https://api.deepseek.com/chat/completions';
const MODEL = 'deepseek-chat';
const SYSTEM_PROMPT = '你是翻译器。把英文技术思考翻译成简体中文，保留代码、路径、工具名、专有名词，不解释，只输出译文。';
const USER_TEXT_LIMIT = 1200;
const MAX_TOKENS = 400;
const TEMPERATURE = 0.2;
const REQUEST_TIMEOUT_MS = 8000;
const MIN_INTERVAL_MS = 8000;
const FAILURE_BACKOFF_MS = 60000;
const CACHE_LIMIT = 64;

function hashText (text) {
  return createHash ('sha256').update (text, 'utf8').digest ('hex');
}

function parseRefValue (raw) {
  let value = String (raw || '').trim ();
  if (value.length >= 2 && value.startsWith ('"') && value.endsWith ('"')) value = value.slice (1, -1);
  else if (value.length >= 2 && value.startsWith ("'") && value.endsWith ("'")) value = value.slice (1, -1);
  const comment = value.indexOf (' #');
  if (comment >= 0) value = value.slice (0, comment).trim ();
  return value;
}

/**
 * Resolve the DeepSeek API key: environment override first, then the DSH
 * credentials store (refs.DEEPSEEK_API_KEY). Returns {key, source} or null.
 * Callers must treat the returned key as a secret.
 */
export function resolveDeepSeekKey (home) {
  const fromEnv = process.env.DEEPSEEK_API_KEY;
  if (typeof fromEnv === 'string' && fromEnv.trim () !== '') return { key: fromEnv.trim (), source: 'env' };
  const directory = typeof home === 'string' && home !== '' ? home : dshHome ();
  let text;
  try {
    text = fs.readFileSync (path.join (directory, '.credentials.yaml'), 'utf8');
  } catch {
    return null;
  }
  let inRefs = false;
  for (const line of text.split ('\n')) {
    if (/^refs:\s*$/u.test (line)) { inRefs = true; continue; }
    if (!inRefs) continue;
    if (line.trim () === '') continue;
    if (!line.startsWith (' ')) { inRefs = false; continue; }
    if (line.startsWith ('    ')) continue;
    const match = /^  ([A-Za-z0-9_./-]+):\s*(.*)$/u.exec (line);
    if (!match) continue;
    if (match[1] !== 'DEEPSEEK_API_KEY') continue;
    const value = parseRefValue (match[2]);
    if (value !== '') return { key: value, source: 'credentials' };
  }
  return null;
}

/** True when the text is (mostly) Simplified Chinese already; such text is not translated. */
export function isMostlyChinese (text) {
  if (typeof text !== 'string' || text === '') return false;
  const cjk = (text.match (/[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]/gu) || []).length;
  if (cjk === 0) return false;
  const latin = (text.match (/[A-Za-z]/gu) || []).length;
  if (latin === 0) return true;
  return cjk / (cjk + latin) >= 0.5;
}

export class ThoughtTranslator {
  constructor ({ enabled = true, log = null, logThrottled = null, home = null, fetchImpl = null } = {}) {
    this.enabled = enabled === true;
    this.log = typeof log === 'function' ? log : () => {};
    this.logThrottled = typeof logThrottled === 'function' ? logThrottled : () => {};
    this.home = typeof home === 'string' && home !== '' ? home : null;
    this.fetchImpl = typeof fetchImpl === 'function' ? fetchImpl : null;
    this.credentials = null;
    this.cache = new Map ();        // sha256 -> translated zh
    this.entries = new Map ();      // agentId -> {hash, zh, state, at}
    this.lastAttemptAt = new Map (); // agentId -> ms
    this.failures = new Map ();     // sha256 -> retryAfter ms
    this.pending = new Map ();      // agentId -> {text, hash}
    this.inFlight = false;
    this.idleWaiters = [];
    if (this.enabled) this.reloadKey ();
  }

  /** Re-read the key (env or credentials store). Never logs the key itself. */
  reloadKey () {
    try {
      this.credentials = resolveDeepSeekKey (this.home || undefined);
    } catch {
      this.credentials = null;
    }
    if (this.credentials) this.log ('thought translation enabled (key source: ' + this.credentials.source + ')');
    else this.log ('thought translation disabled: no DEEPSEEK_API_KEY in env or credentials store');
    return this.credentials;
  }

  /** Current translated thought for a text, or null. Pure read; safe in hot paths. */
  thoughtZhFor (agentId, text) {
    if (typeof agentId !== 'string' || agentId === '') return null;
    if (typeof text !== 'string' || text === '') return null;
    const entry = this.entries.get (agentId);
    if (!entry || entry.hash !== hashText (text)) return null;
    return typeof entry.zh === 'string' ? entry.zh : null;
  }

  /**
   * Schedule a translation when the thought text is new, non-empty, not
   * Chinese and outside the per-agent gap. Never awaits; never touches the tick.
   */
  observe (agentId, text) {
    if (!this.enabled) return;
    if (!this.credentials) return;
    if (typeof agentId !== 'string' || agentId === '') return;
    if (typeof text !== 'string' || text.trim () === '') return;
    const hash = hashText (text);
    const entry = this.entries.get (agentId);
    if (entry && entry.hash === hash) {
      if (entry.state !== 'failed') return;
      if (Date.now () < (this.failures.get (hash) || 0)) return;
    }
    const cached = this.cache.get (hash);
    if (typeof cached === 'string') {
      this.cache.delete (hash);
      this.cache.set (hash, cached);
      this.entries.set (agentId, { hash, zh: cached, state: 'translated', at: Date.now () });
      return;
    }
    if (isMostlyChinese (text)) {
      this.entries.set (agentId, { hash, zh: null, state: 'chinese', at: Date.now () });
      return;
    }
    const now = Date.now ();
    if (now - (this.lastAttemptAt.get (agentId) || 0) < MIN_INTERVAL_MS) return;
    if (now < (this.failures.get (hash) || 0)) return;
    this.pending.set (agentId, { text, hash });
    void this.pump ();
  }

  async pump () {
    if (this.inFlight) return;
    this.inFlight = true;
    try {
      while (this.pending.size > 0) {
        if (!this.enabled) { this.pending.clear (); break; }
        const [agentId, job] = this.pending.entries ().next ().value;
        this.pending.delete (agentId);
        this.lastAttemptAt.set (agentId, Date.now ());
        try {
          const zh = await this.requestTranslation (job.text);
          this.cacheSet (job.hash, zh);
          this.entries.set (agentId, { hash: job.hash, zh, state: 'translated', at: Date.now () });
        } catch (error) {
          const reason = error && Number.isFinite (error.status)
            ? 'HTTP ' + error.status
            : (error && error.name) || 'request failed';
          this.failures.set (job.hash, Date.now () + FAILURE_BACKOFF_MS);
          this.entries.set (agentId, { hash: job.hash, zh: null, state: 'failed', at: Date.now () });
          this.logThrottled ('translate-error', 60000, 'thought translation failed (' + reason + '); keeping original text');
        }
      }
    } finally {
      this.inFlight = false;
      this.resolveIdle ();
    }
  }

  async requestTranslation (text) {
    if (!this.credentials) throw new Error ('no DeepSeek API key');
    const fetchFn = this.fetchImpl || fetch;
    const response = await fetchFn (API_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer ' + this.credentials.key
      },
      body: JSON.stringify ({
        model: MODEL,
        temperature: TEMPERATURE,
        max_tokens: MAX_TOKENS,
        stream: false,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: text.slice (0, USER_TEXT_LIMIT) }
        ]
      }),
      signal: AbortSignal.timeout (REQUEST_TIMEOUT_MS)
    });
    if (!response.ok) {
      const error = new Error ('translation HTTP ' + response.status);
      error.status = response.status;
      throw error;
    }
    const data = await response.json ();
    const choice = data && Array.isArray (data.choices) ? data.choices[0] : null;
    const content = choice && choice.message ? choice.message.content : null;
    if (typeof content !== 'string' || content.trim () === '') throw new Error ('translation returned no text');
    return content.trim ();
  }

  cacheSet (hash, value) {
    this.cache.set (hash, value);
    while (this.cache.size > CACHE_LIMIT) {
      const oldest = this.cache.keys ().next ().value;
      this.cache.delete (oldest);
    }
  }

  /** Wait until queued translations settle (used by --once); resolves on timeout too. */
  drain (timeoutMs = 12000) {
    if (!this.enabled || (!this.inFlight && this.pending.size === 0)) return Promise.resolve ();
    return new Promise ((resolve) => {
      let waiter = null;
      const timer = setTimeout (() => {
        this.idleWaiters = this.idleWaiters.filter ((item) => item !== waiter);
        resolve ();
      }, timeoutMs);
      if (typeof timer.unref === 'function') timer.unref ();
      waiter = () => { clearTimeout (timer); resolve (); };
      this.idleWaiters.push (waiter);
    });
  }

  resolveIdle () {
    const waiters = this.idleWaiters.splice (0);
    for (const wake of waiters) {
      try { wake (); } catch {}
    }
  }

  /** Small diagnostics blob (no text, no key) for the status feed. */
  describe () {
    return {
      enabled: this.enabled,
      keySource: this.credentials ? this.credentials.source : null,
      cached: this.cache.size,
      pending: this.pending.size
    };
  }
}
