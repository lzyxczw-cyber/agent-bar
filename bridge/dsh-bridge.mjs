#!/usr/bin/env node
/**
 * dsh-bridge.mjs — live feed from a running DeepSeek Harness (DSH) Web GUI
 * into a stable local "status.json" file and a Unix-socket NDJSON stream.
 *
 * Data path (read-only unless the opt-in approval control channel is used):
 *   DSH Gateway HTTP  POST /api/session/list      -> sessions + running/title/cwd
 *   DSH Gateway HTTP  POST /api/session/page      -> last tool call of running sessions
 *   DSH Gateway WS    /api/remote.mux ($events)   -> live running status, approvals,
 *                                                    user questions, session add/remove
 *
 * Auth: a browser-session cookie is minted in memory from the durable signing
 * secret in $DSH_HOME/.credentials.yaml (see lib/dsh-auth.mjs).
 * The feed never sends prompts or messages. The optional local control channel
 * (control/request-*.json) may answer an already-pending approval/request via
 * $events/result; it cannot choose commands, send prompts, or answer questions.
 *
 * Output:
 *   bridge/status.json   atomic snapshot, schema version 1
 *   bridge/status.sock   newline-delimited JSON, one {"type":"snapshot",...} per tick
 *
 * Usage: node dsh-bridge.mjs [--url http://127.0.0.1:PORT] [--interval 1000]
 *        [--active-window 15] [--max-agents 12] [--all] [--once] [--no-ws]
 *        [--no-socket] [--out PATH] [--socket PATH] [--verbose]
 *        [--no-translate] [--no-external] [--agents-dir DIR]
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { discoverDsh, cookieFor } from './lib/dsh-auth.mjs';
import { DshRpc, DshRpcError } from './lib/rpc.mjs';
import { ThoughtTranslator } from './lib/translate.mjs';
import { openMux, openEventStream } from './vendor/ws-mux.mjs';

const BRIDGE_DIR = path.dirname (fileURLToPath (import.meta.url));
const SCHEMA_VERSION = 1;
const STATUS_WRITE_HEARTBEAT_MS = 5000;
const EXTERNAL_STALE_MS = 120 * 1000;      // no heartbeat for 2 min -> hide
const EXTERNAL_MAX_AGE_MS = 10 * 60 * 1000; // older reports are ignored entirely
const EXTERNAL_STATUSES = new Set (['running', 'waiting', 'done', 'failed']);

/** External agents report directory (env override wins over the App Support default). */
function defaultAgentsDir () {
  const fromEnv = process.env.AGENTBAR_AGENTS_DIR;
  if (typeof fromEnv === 'string' && fromEnv.trim () !== '') return path.resolve (fromEnv.trim ());
  return path.join (os.homedir (), 'Library', 'Application Support', 'AgentBar', 'agents');
}

function usage () {
  return [
    'node dsh-bridge.mjs [options]',
    '',
    '  --url <origin>        DSH Web GUI origin (default: $DSH_WEB_URL or auto-discovery)',
    '  --interval <ms>       feed tick interval (default 1000)',
    '  --active-window <min> show sessions active within N minutes (default 15; 0 = only running/approvals)',
    '  --max-agents <n>      cap agents in the feed (default 12)',
    '  --all                 include every known session (ignores active-window/max-agents)',
    '  --once                discover + print one snapshot to stdout, then exit',
    '  --no-translate        disable thoughtZh (DeepSeek) translation',
    '  --no-external         ignore external agent reports (AgentBar/agents/*.json)',
    '  --agents-dir <dir>    external agent report directory (env AGENTBAR_AGENTS_DIR also works)',
    '  --no-control          disable the local approval-control channel',
    '  --control-dir <dir>   approval-control directory (default: <bridge>/control)',
    '  --no-ws               HTTP polling only (no approvals; status only)',
    '  --no-socket           do not create status.sock',
    '  --out <file>          status.json path (default: <bridge>/status.json)',
    '  --socket <file>       Unix socket path (default: <bridge>/status.sock)',
    '  --verbose             verbose diagnostics',
    '  --help',
    ''
  ].join ('\n');
}

function parseArgs (argv) {
  const config = {
    url: null,
    intervalMs: 1000,
    activeWindowMs: 15 * 60 * 1000,
    maxAgents: 12,
    all: false,
    once: false,
    ws: true,
    socket: true,
    translate: true,
    external: true,
    agentsDir: defaultAgentsDir (),
    control: true,
    controlDir: path.join (BRIDGE_DIR, 'control'),
    outFile: path.join (BRIDGE_DIR, 'status.json'),
    socketPath: path.join (BRIDGE_DIR, 'status.sock'),
    verbose: false
  };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    const next = () => {
      const value = argv[++index];
      if (value === undefined) throw new Error ('missing value for ' + arg);
      return value;
    };
    if (arg === '--url') config.url = next ();
    else if (arg === '--interval') config.intervalMs = Math.max (250, Number (next ()) || 1000);
    else if (arg === '--active-window') config.activeWindowMs = Math.max (0, Number (next ()) || 0) * 60 * 1000;
    else if (arg === '--max-agents') config.maxAgents = Math.max (1, Number (next ()) || 12);
    else if (arg === '--all') config.all = true;
    else if (arg === '--once') config.once = true;
    else if (arg === '--no-translate') config.translate = false;
    else if (arg === '--no-external') config.external = false;
    else if (arg === '--agents-dir') config.agentsDir = path.resolve (next ());
    else if (arg === '--no-control') config.control = false;
    else if (arg === '--control-dir') config.controlDir = path.resolve (next ());
    else if (arg === '--no-ws') config.ws = false;
    else if (arg === '--no-socket') config.socket = false;
    else if (arg === '--out') config.outFile = path.resolve (next ());
    else if (arg === '--socket') config.socketPath = path.resolve (next ());
    else if (arg === '--verbose') config.verbose = true;
    else if (arg === '--help' || arg === '-h') { process.stdout.write (usage ()); process.exit (0); }
    else throw new Error ('unknown argument: ' + arg);
  }
  return config;
}

function sleep (ms) { return new Promise ((resolve) => setTimeout (resolve, ms)); }

function log (message) {
  process.stderr.write ('[dsh-bridge ' + new Date ().toISOString ().slice (11, 19) + '] ' + message + '\n');
}

function logThrottled (key, everyMs, message) {
  const now = Date.now ();
  const last = logThrottled.last || (logThrottled.last = new Map ());
  if (now - (last.get (key) || 0) < everyMs) return;
  last.set (key, now);
  log (message);
}

function compact (value, max) {
  return String (value === undefined || value === null ? '' : value).replace (/\s+/gu, ' ').trim ().slice (0, max || 80);
}

function summarizeArguments (argsJson) {
  if (argsJson === undefined || argsJson === null) return '';
  if (typeof argsJson !== 'string') return compact (JSON.stringify (argsJson), 80);
  let parsed;
  try { parsed = JSON.parse (argsJson); } catch { return compact (argsJson, 80); }
  if (typeof parsed === 'string') return compact (parsed, 80);
  if (!parsed || typeof parsed !== 'object') return compact (argsJson, 80);
  const preferred = ['command', 'cmd', 'query', 'path', 'file_path', 'url', 'goal', 'instruction', 'text', 'code'];
  for (const key of preferred) {
    if (typeof parsed[key] === 'string' && parsed[key] !== '') return compact (parsed[key], 100);
  }
  for (const value of Object.values (parsed)) {
    if (typeof value === 'string' && value !== '') return compact (value, 100);
  }
  return '';
}

function pickLocalized (value) {
  if (typeof value === 'string') return value;
  if (value && typeof value === 'object') {
    if (typeof value.zh === 'string') return value.zh;
    if (typeof value.en === 'string') return value.en;
    const first = Object.values (value).find ((item) => typeof item === 'string');
    if (first) return first;
  }
  return null;
}

function usageTotal (usage) {
  if (!usage || typeof usage !== 'object') return 0;
  return (Number (usage.uncachedInputTokens) || 0) + (Number (usage.outputTokens) || 0);
}

function textField (value, max) {
  if (typeof value !== 'string') return null;
  const text = value.trim ();
  return text === '' ? null : text.slice (0, max);
}

function numberField (value) {
  if (value === null || value === undefined || value === '') return null;
  const number = Number (value);
  return Number.isFinite (number) ? number : null;
}

function normalizeExternalApprovals (approvals, agentId) {
  if (!Array.isArray (approvals)) return [];
  const rows = [];
  for (let index = 0; index < approvals.length && rows.length < 10; index++) {
    const item = approvals[index];
    if (!item || typeof item !== 'object') continue;
    rows.push ({
      id: textField (item.id, 120) || agentId + ':' + (index + 1),
      kind: 'approval',
      tool: textField (item.tool, 120),
      command: textField (item.command, 300) || textField (item.detail, 300),
      reason: textField (item.reason, 500),
      createdAt: numberField (item.createdAt) || Date.now ()
    });
  }
  return rows;
}

function normalizeExternalSessions (sessions) {
  if (!Array.isArray (sessions)) return [];
  const rows = [];
  for (let index = 0; index < sessions.length && rows.length < 6; index++) {
    const item = sessions[index];
    if (!item || typeof item !== 'object') continue;
    const id = textField (item.id, 80) || 'session-' + index;
    const rawStatus = textField (item.status, 20);
    rows.push ({
      id,
      project: textField (item.project, 160),
      tool: textField (item.tool, 160),
      detail: textField (item.detail, 300),
      status: rawStatus && EXTERNAL_STATUSES.has (rawStatus) ? rawStatus : 'done',
      startedAt: numberField (item.startedAt),
      updatedAt: numberField (item.updatedAt),
      tokens: numberField (item.tokens),
      thought: textField (item.thought, 600)
    });
  }
  return rows;
}

function normalizeExternalProcess (steps) {
  if (!Array.isArray (steps)) return [];
  const rows = [];
  for (const item of steps.slice (-10)) {
    if (!item || typeof item !== 'object') continue;
    rows.push ({
      kind: textField (item.kind, 40) || 'step',
      label: textField (item.label, 60),
      detail: textField (item.detail, 240),
      at: numberField (item.at)
    });
  }
  return rows;
}

/** One external report file -> an agent row (or null when stale/malformed). */
function normalizeExternalAgent (data, filename, stat) {
  if (!data || typeof data !== 'object' || Array.isArray (data)) return null;
  const fallbackId = path.basename (filename, '.json');
  const rawId = textField (data.id, 80) || fallbackId;
  const agentId = 'ext:' + rawId;
  const rawStatus = textField (data.status, 20);
  const status = rawStatus && EXTERNAL_STATUSES.has (rawStatus) ? rawStatus : 'idle';
  const updatedAt = numberField (data.updatedAt);
  const startedAt = numberField (data.startedAt);
  const mtime = Math.round (stat.mtimeMs);
  const age = Date.now () - (updatedAt || mtime);
  if (age > EXTERNAL_MAX_AGE_MS) return null; // very old: ignore (never delete user files)
  if (age > EXTERNAL_STALE_MS) return null;   // no heartbeat: hide
  return {
    id: agentId,
    name: textField (data.name, 120) || rawId,
    status,
    busy: status === 'running',
    tool: textField (data.tool, 160),
    detail: textField (data.detail, 300),
    project: textField (data.project, 160),
    appBundleID: textField (data.appBundleID, 200),
    sessions: normalizeExternalSessions (data.sessions),
    cwd: textField (data.cwd, 500),
    model: textField (data.model, 160),
    preset: textField (data.preset, 160),
    permissions: null,
    origin: 'external',
    parentId: null,
    focus: false,
    lastActivity: updatedAt || startedAt || mtime,
    tokens: numberField (data.tokens),
    thought: textField (data.thought, 1600),
    process: normalizeExternalProcess (data.process),
    approvals: normalizeExternalApprovals (data.approvals, agentId),
    tokensToday: numberField (data.tokens) || 0,
    external: true
  };
}

function normalizeSession (row) {
  const projections = row.projections || {};
  const values = projections.values || {};
  const model = values.modelSelection && values.modelSelection.lastUsed
    ? values.modelSelection.lastUsed.model
    : null;
  return {
    id: row.sessionId,
    title: values.title || null,
    cwd: row.cwd || values.workingDirectory || null,
    running: row.running === true,
    agentAvailable: row.agentAvailable === true,
    blank: row.blank === true,
    updatedAt: Number (row.updatedAt) || 0,
    origin: row.origin || 'session',
    parentSessionId: row.parentSessionId || null,
    asOfSeq: Number.isSafeInteger (projections.asOfSeq) ? projections.asOfSeq : null,
    preset: values.agentPreset || null,
    model,
    permissions: values.permissions ? values.permissions.currentValue || null : null,
    subagents: Array.isArray (values.subagentCatalog) ? values.subagentCatalog : [],
    tokenUsage: values.tokenUsage || null,
    raw: row
  };
}

class DshBridge {
  constructor (config) {
    this.config = config;
    this.dsh = null;           // { origin, source, cookie, secret }
    this.rpc = null;
    this.mux = null;
    this.events = null;
    this.connected = false;
    this.eventsConnected = false;
    this.lastError = null;
    this.nextDiscoveryAt = 0;
    this.sessions = new Map ();
    this.liveStatus = new Map ();
    this.tools = new Map ();
    this.toolCalls = new Map ();
    this.toolCheckedAt = new Map ();
    this.thoughts = new Map ();
    this.processes = new Map ();
    this.externalAgents = [];
    this.translator = new ThoughtTranslator ({
      enabled: config.translate === true,
      log,
      logThrottled
    });
    this.account = null;
    this.accountCheckedAt = 0;
    this.approvals = new Map ();
    // Per-session token baselines for today, persisted so a bridge restart does not
    // re-count a whole session as "today's usage".
    this.usageState = { day: null, sessions: {}, bySession: {}, tokensToday: 0, history: [], since: null };
    this.usageDirty = false;
    this.usageSavedAt = 0;
    this.loadUsageState ();
    this.controlToken = null;
    this.controlDir = config.controlDir;
    this.auditFile = path.join (path.dirname (config.outFile), 'audit.log');
    this.controlProcessing = false;
    this.lastListAt = 0;
    this.lastSnapshot = null;
    this.lastSnapshotKey = null;
    this.lastStatusWriteAt = 0;
    this.tickTimer = null;
    this.socketServer = null;
    this.socketClients = new Set ();
    this.shuttingDown = false;
    this.ticking = false;
    this.tickWanted = false;
    this.startedAt = Date.now ();
    this.focusSessionId = process.env.DSH_SESSION_ID || null;
  }

  async discover () {
    if (Date.now () < this.nextDiscoveryAt) return false;
    try {
      const dsh = await discoverDsh ({ explicitUrl: this.config.url });
      this.dsh = dsh;
      this.rpc = new DshRpc ({ origin: dsh.origin, cookie: dsh.cookie });
      this.connected = true;
      this.lastError = null;
      log ('DSH discovered: ' + dsh.origin + ' (source: ' + dsh.source + ')');
      return true;
    } catch (error) {
      this.connected = false;
      this.rpc = null;
      this.dsh = null;
      this.lastError = error.message;
      this.nextDiscoveryAt = Date.now () + 5000;
      logThrottled ('discover', 10000, 'DSH not reachable: ' + error.message);
      return false;
    }
  }

  async refreshSessions () {
    const items = await this.rpc.listSessions ();
    const next = new Map ();
    for (const row of items) next.set (row.sessionId, normalizeSession (row));
    this.sessions = next;
    this.lastListAt = Date.now ();
    for (const session of this.sessions.values ()) {
      if (session.running) this.liveStatus.set (session.id, true);
      else if (!this.liveStatus.has (session.id)) this.liveStatus.set (session.id, false);
    }
    for (const id of this.liveStatus.keys ()) {
      if (!this.sessions.has (id) && !this.approvalsFor (id).length) this.liveStatus.delete (id);
    }
  }

  /** Resolve the page address for a session (subagent sessions need their durable parent). */
  pageAddressFor (session) {
    const isSubagent = session.origin === 'subagent' || !session.id.startsWith ('session-');
    if (!isSubagent) return { kind: 'session', sessionId: session.id };
    let parentId = session.parentSessionId;
    let mode = 'unknown';
    if (parentId) {
      const parent = this.sessions.get (parentId);
      const entry = parent ? parent.subagents.find ((child) => child.id === session.id) : null;
      if (entry && typeof entry.mode === 'string') mode = entry.mode;
    } else {
      for (const candidate of this.sessions.values ()) {
        const entry = candidate.subagents.find ((child) => child.id === session.id);
        if (entry) { parentId = candidate.id; if (typeof entry.mode === 'string') mode = entry.mode; break; }
      }
    }
    if (!parentId) return null;
    return { kind: 'subagent', parentSessionId: parentId, childSessionId: session.id, mode };
  }

  async refreshTools () {
    const now = Date.now ();
    for (const session of this.sessions.values ()) {
      const interesting = this.liveStatus.get (session.id) === true || this.approvalsFor (session.id).length > 0;
      if (!interesting) { this.tools.delete (session.id); this.toolCalls.delete (session.id); continue; }
      if (session.asOfSeq === null) continue;
      if (now - (this.toolCheckedAt.get (session.id) || 0) < 1200) continue;
      this.toolCheckedAt.set (session.id, now);
      const address = this.pageAddressFor (session);
      if (!address) continue;
      let page;
      try {
        page = await this.rpc.page (address, session.asOfSeq, 8);
      } catch (error) {
        if (this.config.verbose) log ('page ' + session.id + ' failed: ' + (error.code || error.name) + ' ' + error.message);
        this.tools.delete (session.id);
        this.toolCalls.delete (session.id);
        continue;
      }
      const openCalls = new Map ();
      const allCalls = new Map ();
      const steps = [];
      let latestThought = null;
      for (const record of page.records || []) {
        const event = record.event || record;
        const data = event.data || {};
        const at = Number (event.time) || null;
        if (event.type === 'tool/call') {
          const call = { name: data.name, callId: data.callId, detail: summarizeArguments (data.arguments) };
          allCalls.set (data.callId, call);
          openCalls.set (data.callId, call);
          steps.push ({ kind: 'tool', label: data.name || 'tool', detail: call.detail, at });
        } else if (event.type === 'tool/result') {
          const callId = (data.message && data.message.toolCallId) || (data.source && data.source.callId);
          openCalls.delete (callId);
          const failed = data.message && data.message.isError === true;
          steps.push ({ kind: 'result', label: failed ? '工具失败' : '工具完成', detail: null, at });
        } else if (event.type === 'assistant/message') {
          const content = (data.message && Array.isArray (data.message.content)) ? data.message.content : [];
          for (const block of content) {
            if (!block || typeof block !== 'object') continue;
            if (block.type === 'reasoning' && typeof block.text === 'string' && block.text.trim ()) {
              latestThought = block.text;
              steps.push ({ kind: 'think', label: '思考', detail: block.text.slice (0, 240), at });
            } else if (block.type === 'text' && typeof block.text === 'string' && block.text.trim ()) {
              steps.push ({ kind: 'reply', label: '回复', detail: block.text.slice (0, 180), at });
            }
          }
        }
      }
      if (latestThought) this.thoughts.set (session.id, latestThought.slice (0, 1600));
      else this.thoughts.delete (session.id);
      if (steps.length > 0) this.processes.set (session.id, steps.slice (-10));
      else this.processes.delete (session.id);
      this.toolCalls.set (session.id, allCalls);
      if (openCalls.size > 0) {
        const lastCall = Array.from (openCalls.values ()).pop ();
        this.tools.set (session.id, { name: lastCall.name, detail: lastCall.detail, since: now });
      } else {
        this.tools.delete (session.id);
      }
      this.enrichApprovals (session.id);
    }
  }

  /**
   * Read external agent reports (one JSON file per agent) and keep the fresh
   * rows in memory. Missing/unreadable/stale files simply disappear from the
   * feed; report files are never modified or deleted here.
   */
  refreshExternalAgents () {
    if (!this.config.external) { this.externalAgents = []; return; }
    const directory = this.config.agentsDir;
    let names;
    try {
      names = fs.readdirSync (directory);
    } catch (error) {
      if (error.code !== 'ENOENT') logThrottled ('external-dir', 60000, 'cannot read external agents dir (' + error.code + ')');
      this.externalAgents = [];
      return;
    }
    const byId = new Map ();
    for (const name of names) {
      if (!name.endsWith ('.json')) continue;
      const file = path.join (directory, name);
      let stat;
      try { stat = fs.statSync (file); } catch { continue; }
      if (!stat.isFile ()) continue;
      let data;
      try {
        data = JSON.parse (fs.readFileSync (file, 'utf8'));
      } catch {
        logThrottled ('external-json', 60000, 'ignoring invalid external agent report: ' + name);
        continue;
      }
      const row = normalizeExternalAgent (data, name, stat);
      if (!row) continue;
      const previous = byId.get (row.id);
      if (!previous || (row.lastActivity || 0) > (previous.lastActivity || 0)) byId.set (row.id, row);
    }
    if (this.config.verbose && byId.size !== this.externalAgents.length) log ('external agents: ' + byId.size);
    this.externalAgents = Array.from (byId.values ());
  }

  /** Queue thought translations for DSH sessions and external agents (never awaits). */
  prepareTranslations () {
    if (!this.config.translate) return;
    for (const session of this.sessions.values ()) {
      const thought = this.thoughts.get (session.id);
      if (thought) this.translator.observe (session.id, thought);
    }
    for (const row of this.externalAgents) {
      if (row.thought) this.translator.observe (row.id, row.thought);
    }
  }

  approvalsFor (sessionId) {
    const list = [];
    for (const approval of this.approvals.values ()) if (approval.sessionId === sessionId) list.push (approval);
    return list;
  }

  enrichApprovals (sessionId) {
    const calls = this.toolCalls.get (sessionId);
    if (!calls) return;
    for (const approval of this.approvals.values ()) {
      if (approval.sessionId !== sessionId || !approval.callId) continue;
      const call = calls.get (approval.callId);
      if (!call) continue;
      if (call.name) approval.tool = call.name;
      if (call.detail) approval.command = call.detail;
    }
  }

  handleEmit (frame) {
    const event = frame.event;
    const args = Array.isArray (frame.args) ? frame.args : [];
    if (event === 'api-session/status') {
      const id = args[0];
      const running = args[1] === true;
      if (typeof id === 'string') {
        this.liveStatus.set (id, running);
        this.lastListAt = 0;
        this.scheduleTick (250);
      }
    } else if (event === 'api-session/activity') {
      const id = args[0];
      const session = this.sessions.get (id);
      if (session && Number.isFinite (args[1])) session.updatedAt = Number (args[1]);
    } else if (event === 'api-session/added') {
      const row = args[0];
      if (row && typeof row.sessionId === 'string') {
        this.sessions.set (row.sessionId, normalizeSession (row));
        this.lastListAt = 0;
        this.scheduleTick (250);
      }
    } else if (event === 'api-session/removed') {
      const id = args[0];
      if (typeof id === 'string') {
        this.sessions.delete (id);
        this.liveStatus.delete (id);
        this.tools.delete (id);
        this.toolCalls.delete (id);
      }
    } else if (event === 'api-session/error') {
      this.lastListAt = 0;
      this.scheduleTick (500);
    }
    if (this.config.verbose) log ('event ' + event);
  }

  handleWaterfall (frame) {
    const isApproval = frame.event === 'approval/request';
    const isQuestion = frame.event === 'user-questions/request';
    if (!isApproval && !isQuestion) return;
    const request = frame.request || {};
    let reason = pickLocalized (request.displayReason) || (typeof request.reason === 'string' ? request.reason : null);
    if (!reason && isQuestion && Array.isArray (request.questions) && request.questions.length > 0) {
      reason = request.questions[0].question || request.questions[0].header || null;
    }
    const approval = {
      id: frame.eventId,
      kind: isApproval ? 'approval' : 'question',
      sessionId: frame.agentId,
      tool: isApproval ? request.toolName || 'approval' : 'ask_user_question',
      callId: request.callId || null,
      reason,
      command: null,
      createdAt: Date.now ()
    };
    this.approvals.set (approval.id, approval);
    log ('pending ' + approval.kind + ' for ' + approval.sessionId + ' (' + approval.tool + ')');
    this.scheduleTick (100);
  }

  handleCancel (frame) {
    if (frame && typeof frame.eventId === 'string' && this.approvals.delete (frame.eventId)) {
      log ('interaction cancelled: ' + frame.eventId);
      this.scheduleTick (100);
    }
  }

  async eventsLoop () {
    let backoff = 1000;
    while (!this.shuttingDown) {
      if (!this.connected || !this.dsh) { await sleep (500); continue; }
      let mux;
      let events;
      try {
        mux = await openMux ({ baseUrl: this.dsh.origin, cookie: this.dsh.cookie });
        events = openEventStream (mux);
        this.mux = mux;
        this.events = events;
        events.onEmit ((frame) => this.handleEmit (frame));
        events.onWaterfall ((frame) => this.handleWaterfall (frame));
        events.onCancel ((frame) => this.handleCancel (frame));
        events.on ('error', (error) => { if (!this.shuttingDown) logThrottled ('events-error', 10000, 'events error: ' + error.message); });
        const ready = await Promise.race ([
          events.ready,
          sleep (5000).then (() => { throw new Error ('$events ready timeout'); })
        ]);
        this.eventsConnected = true;
        backoff = 1000;
        log ('events stream ready (generation ' + String (ready.clientId).slice (0, 8) + ')');
        await new Promise ((resolve) => {
          events.once ('close', resolve);
          events.once ('error', resolve);
          if (this.shuttingDown) resolve ();
        });
        this.eventsConnected = false;
        if (!this.shuttingDown) log ('events stream closed; reconnecting');
      } catch (error) {
        this.eventsConnected = false;
        if (!this.shuttingDown) logThrottled ('events-connect', 10000, 'events connect failed: ' + error.message);
      } finally {
        this.mux = null;
        this.events = null;
        try { if (events) events.close (); } catch {}
        try { if (mux) await mux.close (); } catch {}
      }
      if (this.shuttingDown) break;
      await sleep (backoff);
      backoff = Math.min (backoff * 2, 15000);
    }
  }

  async refreshAccount () {
    if (!this.rpc) return;
    if (Date.now () - this.accountCheckedAt < 60000) return;
    this.accountCheckedAt = Date.now ();
    try {
      const state = await this.rpc.call ('account/getState', {});
      const links = (state && state.links) || {};
      if (!state || state.status !== 'credential-stored') {
        this.account = { status: (state && state.status) || 'signed-out', usageUrl: links.usageUrl || null, topUpUrl: links.topUpUrl || null };
        return;
      }
      const client = {
        version: process.env.DSH_CLIENT_VERSION || '0.2.2',
        locale: 'zh-CN',
        timezoneOffsetSeconds: -new Date ().getTimezoneOffset () * 60
      };
      const result = await this.rpc.call ('account/getBalance', { client });
      if (result && result.status === 'ready') {
        const wallet = Array.isArray (result.value) ? result.value[0] : null;
        const bonus = Array.isArray (result.bonusWallets) ? result.bonusWallets[0] : null;
        this.account = {
          status: 'ready',
          currency: wallet ? wallet.currency : null,
          balance: wallet ? wallet.balance : null,
          bonusBalance: bonus ? bonus.balance : null,
          usageUrl: links.usageUrl || null,
          topUpUrl: links.topUpUrl || null
        };
      } else {
        this.account = { status: 'failed', usageUrl: links.usageUrl || null, topUpUrl: links.topUpUrl || null };
      }
    } catch (error) {
      this.account = { status: 'failed', error: String (error.message || error).slice (0, 160) };
    }
  }

  usageStatePath () {
    return path.join (path.dirname (this.config.outFile), 'usage-state.json');
  }

  loadUsageState () {
    try {
      const parsed = JSON.parse (fs.readFileSync (this.usageStatePath (), 'utf8'));
      if (parsed && typeof parsed === 'object' && parsed.sessions && typeof parsed.sessions === 'object') {
        this.usageState = {
          day: typeof parsed.day === 'string' ? parsed.day : null,
          sessions: parsed.sessions,
          bySession: parsed.bySession && typeof parsed.bySession === 'object' ? parsed.bySession : {},
          tokensToday: Number (parsed.tokensToday) || 0,
          history: Array.isArray (parsed.history) ? parsed.history.slice (-14) : [],
          since: Number (parsed.since) || null
        };
      }
    } catch {
      // no state yet (or unreadable): start from empty baselines
    }
  }

  saveUsageState () {
    if (!this.usageDirty) return;
    const file = this.usageStatePath ();
    try {
      const temporary = file + '.tmp';
      fs.writeFileSync (temporary, JSON.stringify (this.usageState), { mode: 0o600 });
      fs.renameSync (temporary, file);
      this.usageDirty = false;
      this.usageSavedAt = Date.now ();
    } catch (error) {
      logThrottled ('usage-save', 60000, 'cannot persist usage state: ' + error.message);
    }
  }

  /**
   * Today's token spend, measured as the increase of each session's cumulative
   * usage while we were watching - not the session total. A session that was
   * already running before we looked contributes nothing for the part we missed.
   */
  dailyUsage () {
    const now = new Date ();
    const dayKey = [now.getFullYear (), String (now.getMonth () + 1).padStart (2, '0'), String (now.getDate ()).padStart (2, '0')].join ('-');
    const dayStart = new Date (now.getFullYear (), now.getMonth (), now.getDate ()).getTime ();

    if (!this.usageState || this.usageState.day !== dayKey) {
      const previous = this.usageState && this.usageState.day
        ? { day: this.usageState.day, tokens: Number (this.usageState.tokensToday) || 0 }
        : null;
      const history = Array.isArray (this.usageState && this.usageState.history)
        ? this.usageState.history.slice (-13)
        : [];
      if (previous && previous.tokens > 0) history.push (previous);
      this.usageState = { day: dayKey, sessions: {}, bySession: {}, tokensToday: 0, history, since: Date.now () };
      this.usageDirty = true;
    }
    if (!this.usageState.bySession || typeof this.usageState.bySession !== 'object') {
      this.usageState.bySession = {};
    }
    if (!Array.isArray (this.usageState.history)) this.usageState.history = [];
    if (!this.usageState.since) {
      this.usageState.since = Date.now ();
      this.usageDirty = true;
    }

    const baselines = this.usageState.sessions;
    if (typeof this.usageState.tokensToday !== 'number') {
      this.usageState.tokensToday = 0;
      this.usageDirty = true;
    }
    let gained = 0;
    let sessionsToday = 0;
    const live = new Set ();
    for (const session of this.sessions.values ()) {
      live.add (session.id);
      const total = usageTotal (session.tokenUsage);
      const baseline = baselines[session.id];
      if (typeof baseline === 'number') {
        const delta = total - baseline;
        if (delta > 0) {
          gained += delta;
          this.usageState.bySession[session.id] = (this.usageState.bySession[session.id] || 0) + delta;
          this.usageDirty = true;
        }
      } else {
        // First sighting today: count from here on instead of assuming the whole
        // session total happened today (that is what inflated the number before).
        this.usageDirty = true;
      }
      baselines[session.id] = total;
      if ((session.updatedAt || 0) >= dayStart) sessionsToday++;
    }
    // Accumulate into the day's running total: each tick only sees the increment
    // since the previous tick, so a per-call local would reset the meter.
    if (gained > 0) {
      this.usageState.tokensToday += gained;
      this.usageDirty = true;
    }
    for (const id of Object.keys (baselines)) {
      if (!live.has (id)) {
        delete baselines[id];
        this.usageDirty = true;
      }
    }

    if (Date.now () - this.usageSavedAt > 30000) this.saveUsageState ();
    return {
      tokensToday: this.usageState.tokensToday,
      sessionsToday,
      since: this.usageState.since,
      day: dayKey,
      history: this.usageState.history,
      byAgent: this.usageState.bySession
    };
  }

  buildAgents () {
    const now = Date.now ();
    const rows = [];
    const ids = new Set ();
    for (const session of this.sessions.values ()) {
      const approvals = this.approvalsFor (session.id);
      const running = this.liveStatus.get (session.id) === true || (this.liveStatus.get (session.id) === undefined && session.running);
      const active = running || approvals.length > 0 || (now - session.updatedAt <= this.config.activeWindowMs);
      if (!active && !this.config.all) continue;
      const tool = this.tools.get (session.id) || null;
      const status = approvals.length > 0 ? 'approval' : running ? (tool ? 'running' : 'running') : 'idle';
      const cwd = session.cwd || '';
      const thought = this.thoughts.get (session.id) || null;
      rows.push ({
        id: session.id,
        name: session.title || (cwd ? path.basename (cwd) : session.id.slice (0, 18)),
        status,
        busy: running,
        tool: tool ? tool.name : null,
        detail: tool ? tool.detail : null,
        project: cwd ? path.basename (cwd) : null,
        cwd: cwd || null,
        model: session.model,
        preset: session.preset,
        permissions: session.permissions,
        origin: session.origin,
        parentId: session.parentSessionId,
        focus: session.id === this.focusSessionId,
        lastActivity: session.updatedAt || null,
        tokens: usageTotal (session.tokenUsage),
        tokensToday: (this.usageState.bySession && Number.isFinite (this.usageState.bySession[session.id])) ? this.usageState.bySession[session.id] : 0,
        thought,
        thoughtZh: this.translator.thoughtZhFor (session.id, thought),
        process: this.processes.get (session.id) || [],
        approvals: approvals.map ((approval) => ({
          id: approval.id,
          kind: approval.kind,
          tool: approval.tool,
          command: approval.command || approval.reason || null,
          reason: approval.reason || null,
          createdAt: approval.createdAt
        })),
        external: false
      });
      ids.add (session.id);
    }
    for (const approval of this.approvals.values ()) {
      if (ids.has (approval.sessionId)) continue;
      rows.push ({
        id: approval.sessionId,
        name: approval.sessionId.slice (0, 18),
        status: 'approval',
        busy: true,
        tool: null,
        detail: null,
        project: null,
        cwd: null,
        model: null,
        preset: null,
        origin: 'unknown',
        parentId: null,
        focus: false,
        lastActivity: null,
        tokens: null,
        thought: null,
        thoughtZh: null,
        process: [],
        approvals: [{ id: approval.id, kind: approval.kind, tool: approval.tool, command: approval.command || approval.reason || null, reason: approval.reason || null, createdAt: approval.createdAt }],
        external: false
      });
    }
    for (const external of this.externalAgents) {
      rows.push ({ ...external, thoughtZh: this.translator.thoughtZhFor (external.id, external.thought) });
    }
    const rank = (row) => (row.status === 'approval' ? 0 : (row.busy || row.status === 'waiting') ? 1 : 2);
    rows.sort ((a, b) => rank (a) - rank (b) || (b.lastActivity || 0) - (a.lastActivity || 0));
    if (!this.config.all && rows.length > this.config.maxAgents) rows.length = this.config.maxAgents;
    return rows;
  }

  buildSnapshot () {
    const usage = this.dailyUsage ();
    const agents = this.buildAgents ();
    const running = agents.filter ((agent) => agent.busy).length;
    const approvals = agents.reduce ((total, agent) => total + agent.approvals.length, 0);
    const snapshot = {
      schema: SCHEMA_VERSION,
      ts: Date.now (),
      bridge: {
        pid: process.pid,
        startedAt: this.startedAt,
        uptimeMs: Date.now () - this.startedAt,
        focusSessionId: this.focusSessionId,
        translate: this.translator.describe (),
        control: this.controlToken ? { enabled: true, dir: this.controlDir } : { enabled: false }
      },
      dsh: {
        url: this.dsh ? this.dsh.origin : (this.config.url || null),
        source: this.dsh ? this.dsh.source : null,
        connected: this.connected,
        eventsConnected: this.eventsConnected,
        error: this.connected ? null : this.lastError,
        sessionsKnown: this.sessions.size
      },
      counts: { agents: agents.length, running, approvals },
      usage,
      account: this.account,
      agents
    };
    return snapshot;
  }

  writeStatus (snapshot) {
    const key = JSON.stringify ({ dsh: snapshot.dsh, counts: snapshot.counts, agents: snapshot.agents, usage: snapshot.usage, account: snapshot.account });
    const changed = key !== this.lastSnapshotKey;
    const now = Date.now ();
    if (changed || now - this.lastStatusWriteAt >= STATUS_WRITE_HEARTBEAT_MS) {
      const temporary = this.config.outFile + '.tmp';
      try {
        fs.writeFileSync (temporary, JSON.stringify (snapshot, null, 2) + '\n');
        fs.chmodSync (temporary, 0o600);
        fs.renameSync (temporary, this.config.outFile);
      } catch (error) {
        logThrottled ('status-write', 10000, 'cannot write status file: ' + error.message);
      }
      this.lastStatusKey = key;
      this.lastStatusWriteAt = now;
    }
    this.lastSnapshotKey = key;
    this.lastSnapshot = snapshot;
    const line = JSON.stringify ({ type: 'snapshot', ...snapshot }) + '\n';
    for (const client of this.socketClients) {
      try { client.write (line); } catch { this.socketClients.delete (client); }
    }
  }

  scheduleTick (delayMs) {
    this.tickWanted = true;
    if (this.tickTimer) return;
    this.tickTimer = setTimeout (() => {
      this.tickTimer = null;
      void this.tick ();
    }, delayMs === undefined ? 0 : delayMs);
  }

  async tick () {
    if (this.shuttingDown) return;
    if (this.ticking) { this.tickWanted = true; return; }
    this.ticking = true;
    this.tickWanted = false;
    try {
      if (!this.connected || !this.rpc) await this.discover ();
      if (this.connected && this.rpc) {
        if (this.sessions.size === 0 || Date.now () - this.lastListAt > 2500) await this.refreshSessions ();
        await this.refreshTools ();
        await this.refreshAccount ();
      }
      this.refreshExternalAgents ();
      this.prepareTranslations ();
      await this.processApprovalControl ();
      this.writeStatus (this.buildSnapshot ());
    } catch (error) {
      if (error instanceof DshRpcError && error.code === 'auth/unauthorized') {
        this.connected = false;
        this.lastError = error.message;
        this.rpc = null;
        this.dsh = null;
        logThrottled ('auth', 10000, 'DSH auth rejected; re-discovering');
      } else if (error.name === 'DshNetworkError' || error.code === 'client/network') {
        this.connected = false;
        this.lastError = error.message;
        this.rpc = null;
        this.dsh = null;
        logThrottled ('network', 10000, 'DSH connection lost: ' + error.message);
      } else {
        this.lastError = (error.code ? error.code + ': ' : '') + error.message;
        logThrottled ('tick-error', 10000, 'tick error: ' + this.lastError);
      }
      try { this.writeStatus (this.buildSnapshot ()); } catch {}
    } finally {
      this.ticking = false;
      if (this.tickWanted && !this.shuttingDown) this.scheduleTick (50);
    }
  }

  startControl () {
    if (!this.config.control) return;
    const dir = this.controlDir;
    try {
      fs.mkdirSync (dir, { recursive: true, mode: 0o700 });
      fs.chmodSync (dir, 0o700);
      // A new token invalidates any request files left over from a previous run.
      for (const name of fs.readdirSync (dir)) {
        if (name.startsWith ('request-') && name.endsWith ('.json')) {
          try { fs.unlinkSync (path.join (dir, name)); } catch {}
        }
      }
      this.controlToken = crypto.randomBytes (32).toString ('hex');
      const tokenFile = path.join (dir, 'token');
      fs.writeFileSync (tokenFile, this.controlToken + '\n', { mode: 0o600 });
      fs.chmodSync (tokenFile, 0o600);
      log ('approval control ready: ' + dir);
    } catch (error) {
      this.controlToken = null;
      log ('approval control unavailable: ' + error.message);
    }
  }

  auditControl (entry) {
    try {
      const line = JSON.stringify ({ ts: new Date ().toISOString (), ...entry }) + '\n';
      fs.appendFileSync (this.auditFile, line, { mode: 0o600 });
      fs.chmodSync (this.auditFile, 0o600);
    } catch (error) {
      logThrottled ('audit-write', 10000, 'cannot write approval audit: ' + error.message);
    }
  }

  validateControlRequest (request) {
    if (!request || typeof request !== 'object' || Array.isArray (request)) return { ok: false, reason: 'invalid-request' };
    if (request.schema !== 1) return { ok: false, reason: 'invalid-schema' };
    if (typeof request.approvalId !== 'string' || request.approvalId === '') return { ok: false, reason: 'invalid-approval-id' };
    if (request.decision !== 'allowed-once' && request.decision !== 'rejected') return { ok: false, reason: 'invalid-decision' };
    if (typeof request.token !== 'string' || request.token.length !== this.controlToken.length) return { ok: false, reason: 'invalid-token' };
    const supplied = Buffer.from (request.token);
    const expected = Buffer.from (this.controlToken);
    if (supplied.length !== expected.length || !crypto.timingSafeEqual (supplied, expected)) return { ok: false, reason: 'invalid-token' };
    if (Number.isFinite (request.requestedAt) && Date.now () - request.requestedAt > 60_000) return { ok: false, reason: 'expired-request' };
    return { ok: true };
  }

  safeUnlink (file) {
    try { fs.unlinkSync (file); } catch {}
  }

  /**
   * Consume local approval decisions written by the notch UI into control/.
   * This is the only write path in the bridge: a decision for an already
   * pending approval/request event, answered through $events/result.
   * It never sends prompts, never chooses arbitrary commands, and every
   * attempt is appended to audit.log.
   */
  async processApprovalControl () {
    if (!this.controlToken || this.controlProcessing) return;
    this.controlProcessing = true;
    try {
      let names;
      try {
        names = fs.readdirSync (this.controlDir).filter ((name) => name.startsWith ('request-') && name.endsWith ('.json'));
      } catch { return; }
      names.sort ();
      for (const name of names.slice (0, 4)) {
        const file = path.join (this.controlDir, name);
        let stat;
        try { stat = fs.statSync (file); } catch { continue; }
        let request;
        try { request = JSON.parse (fs.readFileSync (file, 'utf8')); }
        catch {
          this.safeUnlink (file);
          this.auditControl ({ source: 'notch', result: 'invalid-json', file: name });
          continue;
        }
        const valid = this.validateControlRequest (request);
        if (!valid.ok) {
          this.safeUnlink (file);
          this.auditControl ({ source: 'notch', result: valid.reason, file: name });
          continue;
        }
        const approval = this.approvals.get (request.approvalId);
        if (!approval) {
          this.safeUnlink (file);
          this.auditControl ({ source: 'notch', result: 'stale', approvalId: request.approvalId, decision: request.decision });
          continue;
        }
        if (approval.kind !== 'approval') {
          this.safeUnlink (file);
          this.auditControl ({ source: 'notch', result: 'unsupported-kind', approvalId: request.approvalId, kind: approval.kind });
          continue;
        }
        if (request.sessionId && request.sessionId !== approval.sessionId) {
          this.safeUnlink (file);
          this.auditControl ({ source: 'notch', result: 'session-mismatch', approvalId: request.approvalId });
          continue;
        }
        const ageMs = Date.now () - stat.mtimeMs;
        if (!this.eventsConnected || !this.events) {
          if (ageMs > 15000) {
            this.safeUnlink (file);
            this.auditControl ({ source: 'notch', result: 'events-offline', approvalId: request.approvalId, decision: request.decision });
          }
          continue;
        }
        try {
          await this.events.answer ({
            eventId: approval.id,
            outcome: { kind: 'result', value: request.decision }
          });
          this.approvals.delete (approval.id);
          this.safeUnlink (file);
          this.auditControl ({
            source: 'notch', result: 'ok', approvalId: approval.id,
            sessionId: approval.sessionId, tool: approval.tool,
            command: compact (approval.command || approval.reason || '', 300),
            decision: request.decision
          });
          log ('approval answered: ' + approval.id + ' -> ' + request.decision);
          this.scheduleTick (200);
        } catch (error) {
          const entry = {
            source: 'notch', result: 'error', approvalId: approval.id, decision: request.decision,
            error: compact (error.code ? error.code + ': ' + error.message : error.message, 200)
          };
          if (ageMs <= 15000) {
            this.auditControl (entry);
            logThrottled ('control-answer', 5000, 'approval answer failed: ' + entry.error);
          } else {
            this.safeUnlink (file);
            this.auditControl ({ ...entry, result: 'expired' });
          }
        }
      }
    } finally {
      this.controlProcessing = false;
    }
  }

  async startSocket () {
    if (!this.config.socket) return;
    try {
      const stat = fs.lstatSync (this.config.socketPath);
      if (stat.isSocket ()) fs.unlinkSync (this.config.socketPath);
      else throw new Error (this.config.socketPath + ' exists and is not a socket');
    } catch (error) {
      if (error.code !== 'ENOENT') { log ('socket unavailable: ' + error.message); return; }
    }
    const server = net.createServer ((client) => {
      this.socketClients.add (client);
      client.on ('error', () => this.socketClients.delete (client));
      client.on ('close', () => this.socketClients.delete (client));
      if (this.lastSnapshot) {
        try { client.write (JSON.stringify ({ type: 'snapshot', ...this.lastSnapshot }) + '\n'); } catch {}
      }
    });
    server.on ('error', (error) => log ('socket server error: ' + error.message));
    await new Promise ((resolve) => server.listen (this.config.socketPath, resolve));
    fs.chmodSync (this.config.socketPath, 0o600);
    this.socketServer = server;
    log ('status socket: ' + this.config.socketPath);
  }

  async shutdown (reason) {
    if (this.shuttingDown) return;
    this.shuttingDown = true;
    log ('stopping (' + reason + ')');
    if (this.tickTimer) clearTimeout (this.tickTimer);
    try { if (this.events) this.events.close (); } catch {}
    try { if (this.mux) await this.mux.close (); } catch {}
    for (const client of this.socketClients) { try { client.destroy (); } catch {} }
    this.socketClients.clear ();
    if (this.socketServer) {
      await new Promise ((resolve) => this.socketServer.close (resolve));
      try { fs.unlinkSync (this.config.socketPath); } catch {}
    }
    process.exit (0);
  }
}

async function main () {
  let config;
  try { config = parseArgs (process.argv.slice (2)); } catch (error) {
    process.stderr.write (error.message + '\n\n' + usage ());
    process.exit (2);
  }
  const bridge = new DshBridge (config);

  if (config.once) {
    const found = await bridge.discover ();
    if (!found) { process.stdout.write (JSON.stringify ({ ok: false, error: bridge.lastError }) + '\n'); process.exit (1); }
    await bridge.refreshSessions ();
    await bridge.refreshTools ();
    await bridge.refreshAccount ();
    bridge.refreshExternalAgents ();
    bridge.prepareTranslations ();
    if (config.translate) await bridge.translator.drain (12000);
    process.stdout.write (JSON.stringify (bridge.buildSnapshot (), null, 2) + '\n');
    return;
  }

  log ('starting (bridge dir ' + BRIDGE_DIR + ')');
  bridge.startControl ();
  await bridge.startSocket ();
  await bridge.discover ();
  if (config.ws) void bridge.eventsLoop ();
  bridge.scheduleTick (0);
  const timer = setInterval (() => bridge.scheduleTick (0), config.intervalMs);
  timer.unref ();
  process.on ('SIGINT', () => void bridge.shutdown ('SIGINT'));
  process.on ('SIGTERM', () => void bridge.shutdown ('SIGTERM'));
}

main ().catch ((error) => {
  log ('fatal: ' + (error && error.stack ? error.stack : String (error)));
  process.exit (1);
});
