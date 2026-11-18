#!/usr/bin/env node
/**
 * agentbar-app-adapters.mjs — read-only adapters for local desktop agents.
 *
 *   node tools/agentbar-app-adapters.mjs          # watch all local apps
 *   node tools/agentbar-app-adapters.mjs --once   # print parsed reports
 *
 * Supported local apps (each can report multiple concurrent sessions):
 *   Codex (ChatGPT.app)  ~/.codex/thread_history_1.sqlite
 *   WorkBuddy            ~/.workbuddy/traces/<worker>/trace-*.jsonl
 *   Grok Bot             .../Grok Bot/sand-client-persistence/<hash>.blob
 *   Hermes               $HERMES_HOME/state.db (default ~/.hermes/state.db)
 *
 * Writes only the generic external-agent report files under
 * ~/Library/Application Support/AgentBar/agents/. Never writes app state.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  aggregateApp,
  codexStandbyStatus,
  grokActivityStatus,
  hermesIdleReport,
  hermesMessageSelect,
  hermesSessionSelect,
  inferHermesRunning,
  latestHermesMessages,
  normalizeHermesSession,
  workbuddyStandbyStatus
} from './lib/adapter-logic.mjs';

const HOME = os.homedir();
const APP_SUPPORT = path.join(HOME, 'Library', 'Application Support', 'AgentBar');
const AGENTS_DIR = path.join(APP_SUPPORT, 'agents');
const LOCK_FILE = path.join(APP_SUPPORT, 'agentbar-app-adapters.lock');
const SOURCE = 'agentbar-app-adapters';
const TICK_MS = 3000;

const once = process.argv.includes('--once');
const owned = new Map(); // group -> Set(report ids)
let locked = false;
let appGoneSince = 0;
let shuttingDown = false;

function compact(value, limit = 180) {
  if (value === null || value === undefined) return null;
  const text = String(value).replace(/\s+/g, ' ').trim();
  if (!text) return null;
  return text.length > limit ? text.slice(0, limit) + '…' : text;
}

function pgrep(pattern) {
  const result = spawnSync('/usr/bin/pgrep', ['-f', pattern], { encoding: 'utf8' });
  return result.status === 0;
}

function appRunning(pattern) {
  return pgrep(pattern);
}

function agentBarRunning() {
  return pgrep('/Agent Bar.app/Contents/MacOS/AgentBar') ||
    pgrep('/AgentBar.app/Contents/MacOS/AgentBar');
}

function sqliteJSON(db, sql) {
  const result = spawnSync('/usr/bin/sqlite3', ['-readonly', '-json', db, sql], {
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024
  });
  if (result.status !== 0 || !result.stdout.trim()) return [];
  try { return JSON.parse(result.stdout); } catch { return []; }
}

function readJSON(value) {
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return null; }
}

function writeReport(report) {
  fs.mkdirSync(AGENTS_DIR, { recursive: true, mode: 0o700 });
  const now = Date.now();
  const payload = {
    id: report.id,
    source: SOURCE,
    updatedAt: now,
    startedAt: report.startedAt || now,
    name: report.name,
    status: report.status,
    project: report.project || null,
    tool: report.tool || null,
    detail: report.detail || null,
    thought: report.thought || null,
    tokens: report.tokens || null,
    appBundleID: report.appBundleID || null,
    sessions: report.sessions || [],
    approvals: [],
    process: report.process || []
  };
  const file = path.join(AGENTS_DIR, report.id + '.json');
  const temporary = file + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(payload, null, 2), { mode: 0o600 });
  fs.chmodSync(temporary, 0o600);
  fs.renameSync(temporary, file);
}

function removeReport(id) {
  try { fs.unlinkSync(path.join(AGENTS_DIR, id + '.json')); } catch {}
}

function syncGroup(group, reports) {
  const previous = owned.get(group) || new Set();
  const next = new Set(reports.map((report) => report.id));
  for (const id of previous) {
    if (!next.has(id)) removeReport(id);
  }
  for (const report of reports) writeReport(report);
  owned.set(group, next);
}

function isOurReport(file) {
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!data || typeof data.id !== 'string') return false;
    if (data.source === SOURCE) return true;
    return data.id === 'codex' || data.id === 'grok' || data.id === 'workbuddy' || data.id === 'hermes' ||
      data.id.startsWith('codex-') || data.id.startsWith('grok-') ||
      data.id.startsWith('workbuddy-') || data.id.startsWith('hermes-');
  } catch {
    return false;
  }
}

function cleanupOwnReports() {
  let names;
  try { names = fs.readdirSync(AGENTS_DIR); } catch { return; }
  for (const name of names) {
    if (!name.endsWith('.json')) continue;
    const file = path.join(AGENTS_DIR, name);
    if (isOurReport(file)) {
      try { fs.unlinkSync(file); } catch {}
    }
  }
}

function acquireLock() {
  fs.mkdirSync(APP_SUPPORT, { recursive: true, mode: 0o700 });
  try {
    fs.writeFileSync(LOCK_FILE, String(process.pid), { flag: 'wx', mode: 0o600 });
    locked = true;
    return true;
  } catch {
    try {
      const pid = Number(fs.readFileSync(LOCK_FILE, 'utf8'));
      if (pid > 0) {
        process.kill(pid, 0);
        return false;
      }
    } catch {}
    try { fs.unlinkSync(LOCK_FILE); } catch {}
    try {
      fs.writeFileSync(LOCK_FILE, String(process.pid), { flag: 'wx', mode: 0o600 });
      locked = true;
      return true;
    } catch {
      return false;
    }
  }
}

function shutdown(code = 0) {
  if (shuttingDown) return;
  shuttingDown = true;
  if (!once) {
    cleanupOwnReports();
    if (locked) {
      try { fs.unlinkSync(LOCK_FILE); } catch {}
      locked = false;
    }
  }
  process.exit(code);
}

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => shutdown(0));
}

// MARK: Codex

const CODEX_DB = path.join(HOME, '.codex', 'thread_history_1.sqlite');
const CODEX_APP = '/Applications/ChatGPT.app/Contents/MacOS/ChatGPT';

function codexIdleReport() {
  const last = sqliteJSON(CODEX_DB,
    "select thread_id, status, started_at, completed_at from thread_turns order by started_at desc limit 1;")[0];
  const now = Date.now();
  const status = codexStandbyStatus(last, now);
  const tool = status === 'done' ? '本轮完成' : (status === 'failed' ? '失败' : '空闲');
  return {
    id: 'codex',
    name: 'Codex',
    status,
    project: 'Codex',
    tool,
    detail: last ? last.status : null,
    startedAt: last && last.started_at ? Number(last.started_at) * 1000 : now
  };
}

function codexTurnReport(turn) {
  const threadId = String(turn.thread_id);
  const turnId = String(turn.turn_id);
  const quotedThread = threadId.replace(/'/g, "''");
  const quotedTurn = turnId.replace(/'/g, "''");
  const items = sqliteJSON(CODEX_DB,
    "select item_type, substr(item_json, 1, 4000) as item_json from thread_items where thread_id = '" +
    quotedThread + "' and turn_id = '" + quotedTurn + "' order by rollout_ordinal desc limit 10;");
  if (items.length === 0) return null;
  let project = 'Codex';
  let tool = '思考中';
  let thought = null;
  const process = [];
  for (let index = items.length - 1; index >= 0; index--) {
    const item = items[index];
    const payload = readJSON(item.item_json);
    if (!payload || typeof payload !== 'object') continue;
    const type = String(item.item_type || payload.type || '');
    const at = payload.timestampMs || payload.startedAtMs || null;
    if (type === 'commandExecution' && payload.command) {
      tool = 'Bash: ' + compact(payload.command, 160);
      if (payload.cwd) project = path.basename(String(payload.cwd)) || project;
      process.push({ kind: 'tool', label: 'Bash', detail: compact(payload.command, 180), at });
    } else if (type === 'fileChange') {
      const first = Array.isArray(payload.changes) && payload.changes[0] ? payload.changes[0] : null;
      tool = first ? 'Edit: ' + path.basename(String(first.path || '')) : '编辑文件';
      process.push({ kind: 'tool', label: first ? 'Edit' : 'File', detail: first ? compact(first.path, 160) : null, at });
    } else if (type === 'reasoning') {
      const content = Array.isArray(payload.content) ? payload.content.join(' ') : '';
      thought = compact(content, 600) || thought;
      process.push({ kind: 'think', label: '思考', detail: compact(content, 160), at });
    } else if (type === 'agentMessage') {
      tool = '回复';
      process.push({ kind: 'reply', label: '回复', detail: compact(payload.text, 160), at });
    }
  }
  return {
    id: 'codex-' + threadId.slice(0, 8),
    name: 'Codex',
    status: 'running',
    project,
    tool,
    thought,
    startedAt: Number(turn.started_at) * 1000,
    process: process.slice(-6)
  };
}

function codexReports() {
  if (!fs.existsSync(CODEX_DB) || !appRunning(CODEX_APP)) return [];
  const cutoff = Math.floor(Date.now() / 1000) - 12 * 60 * 60;
  const active = sqliteJSON(CODEX_DB,
    "select thread_id, turn_id, status, started_at from thread_turns where status = 'inProgress' and started_at >= " +
    cutoff + " order by started_at desc limit 4;");
  const reports = [];
  const seen = new Set();
  for (const turn of active) {
    const report = codexTurnReport(turn);
    if (!report || seen.has(report.id)) continue;
    seen.add(report.id);
    reports.push(report);
    if (reports.length >= 3) break;
  }
  return reports.length > 0 ? reports : [codexIdleReport()];
}

// MARK: WorkBuddy

const WORKBUDDY_APP = '/Applications/WorkBuddy.app/Contents/MacOS/Electron';
const WORKBUDDY_TRACES = path.join(HOME, '.workbuddy', 'traces');

function newestFiles(root, suffix, maxAgeMs, maxDepth = 3) {
  const found = [];
  const cutoff = Date.now() - maxAgeMs;
  function walk(dir, depth) {
    if (depth < 0) return;
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full, depth - 1);
      else if (entry.name.endsWith(suffix)) {
        try {
          const stat = fs.statSync(full);
          if (stat.mtimeMs >= cutoff) found.push({ file: full, mtime: stat.mtimeMs });
        } catch {}
      }
    }
  }
  walk(root, maxDepth);
  return found.sort((a, b) => b.mtime - a.mtime);
}

function readTraceStart(file) {
  try {
    const fd = fs.openSync(file, 'r');
    const buffer = Buffer.alloc(8192);
    const bytes = fs.readSync(fd, buffer, 0, buffer.length, 0);
    fs.closeSync(fd);
    const line = buffer.toString('utf8', 0, bytes).split('\n')[0];
    const parsed = JSON.parse(line);
    return parsed && parsed.type === 'trace_start' ? parsed.trace : null;
  } catch { return null; }
}

function parseWorkBuddyTrace(file) {
  let text = '';
  let start = 0;
  try {
    const stat = fs.statSync(file);
    start = Math.max(0, stat.size - 128 * 1024);
    const fd = fs.openSync(file, 'r');
    const buffer = Buffer.alloc(stat.size - start);
    fs.readSync(fd, buffer, 0, buffer.length, start);
    fs.closeSync(fd);
    text = buffer.toString('utf8');
  } catch {
    return null;
  }
  const lines = text.split('\n');
  if (start > 0) lines.shift();
  const openSpans = new Map();
  let latestSpan = null;
  for (const line of lines) {
    if (!line.trim()) continue;
    let event;
    try { event = JSON.parse(line); } catch { continue; }
    const span = event.span;
    if (!span || !span.spanId) continue;
    if (event.type === 'span_start') {
      latestSpan = span;
      if (span.endedAt === null || span.endedAt === undefined) openSpans.set(span.spanId, span);
    } else if (event.type === 'span_end') {
      openSpans.delete(span.spanId);
    }
  }
  return Array.from(openSpans.values()).length > 0
    ? Array.from(openSpans.values())
    : (latestSpan ? [latestSpan] : []);
}

function workbuddyReports() {
  if (!appRunning(WORKBUDDY_APP)) return [];
  const traces = newestFiles(WORKBUDDY_TRACES, '.jsonl', 10 * 60 * 1000);
  const reports = [];
  const seen = new Set();
  for (const entry of traces) {
    if (reports.length >= 3) break;
    if (Date.now() - entry.mtime > 5 * 60 * 1000) continue;
    const trace = readTraceStart(entry.file);
    if (!trace || (trace.endedAt !== null && trace.endedAt !== undefined)) continue;
    const spans = parseWorkBuddyTrace(entry.file);
    const current = spans[spans.length - 1];
    const agentName = spans.map((span) => span.agentName).filter(Boolean).slice(-1)[0] || null;
    const id = 'workbuddy-' + String(trace.traceId || crypto.createHash('sha1').update(entry.file).digest('hex')).slice(0, 8);
    if (seen.has(id)) continue;
    seen.add(id);
    reports.push({
      id,
      name: 'WorkBuddy',
      status: 'running',
      project: agentName || 'WorkBuddy',
      tool: current && current.name ? current.name : '启动中',
      detail: current && current.type ? 'span: ' + current.type : null,
      startedAt: trace.startedAt ? Date.parse(trace.startedAt) : Date.now(),
      tokens: Number(trace.totalTokens) || null,
      process: spans.slice(-6).map((span) => ({
        kind: 'tool',
        label: span.name,
        detail: span.type,
        at: span.startedAt ? Date.parse(span.startedAt) : null
      }))
    });
  }
  if (reports.length > 0) return reports;
  const last = traces[0];
  const trace = last ? readTraceStart(last.file) : null;
  const now = Date.now();
  const status = workbuddyStandbyStatus(trace, now);
  return [{
    id: 'workbuddy',
    name: 'WorkBuddy',
    status,
    project: 'WorkBuddy',
    tool: status === 'done' ? '本轮完成' : '空闲',
    startedAt: trace && trace.startedAt ? Date.parse(trace.startedAt) : now
  }];
}

// MARK: Grok Bot

const GROK_APP = '/Applications/Grok Bot.app/Contents/MacOS/Grok Bot';
const GROK_DIR = path.join(HOME, 'Library', 'Application Support', 'Grok Bot', 'sand-client-persistence');

function grokCandidates() {
  try {
    return fs.readdirSync(GROK_DIR)
      .filter((name) => name.endsWith('.blob'))
      .map((name) => {
        const file = path.join(GROK_DIR, name);
        try { return { file, name, mtime: fs.statSync(file).mtimeMs }; } catch { return null; }
      })
      .filter(Boolean)
      .sort((a, b) => b.mtime - a.mtime)
      .slice(0, 12);
  } catch {
    return [];
  }
}

function grokEntries(candidate) {
  try {
    const data = JSON.parse(fs.readFileSync(candidate.file, 'utf8'));
    const entries = data && data.value && Array.isArray(data.value.entries) ? data.value.entries : null;
    if (!entries || entries.length === 0) return null;
    return { entries, id: 'grok-' + crypto.createHash('sha1').update(candidate.name).digest('hex').slice(0, 8) };
  } catch {
    return null;
  }
}

function grokReports() {
  if (!appRunning(GROK_APP)) return [];
  let idle = null;
  const reports = [];
  for (const candidate of grokCandidates()) {
    if (Date.now() - candidate.mtime > 10 * 60 * 1000) break;
    const parsed = grokEntries(candidate);
    if (!parsed) continue;
    const entries = parsed.entries;
    const latestUser = entries.filter((entry) => entry && entry.role === 'user').slice(-1)[0] || null;
    const assistant = entries.filter((entry) => entry && entry.role === 'assistant').slice(-1)[0] || null;
    const latestSend = entries.filter((entry) => entry && entry.kind === 'send-message').slice(-1)[0] || null;
    const assistantForLatest = latestSend
      ? entries.some((entry) => entry && entry.role === 'assistant' && entry.requestId === latestSend.requestId)
      : true;
    const streaming = entries.some((entry) => entry && entry.isStreaming === true);
    const now = Date.now();
    const activity = grokActivityStatus({
      streaming,
      sentAt: latestSend ? latestSend.timestampMs : null,
      assistantReplied: assistantForLatest,
      now
    });
    const agentName = assistant && assistant.toAgent && assistant.toAgent.name ? assistant.toAgent.name : null;
    const base = {
      name: 'Grok Bot',
      project: agentName || 'Grok Bot',
      detail: latestUser ? compact(latestUser.content, 200) : null,
      startedAt: latestSend && latestSend.timestampMs ? Number(latestSend.timestampMs) : now
    };
    if (activity === 'running') {
      reports.push({
        ...base,
        id: parsed.id,
        status: 'running',
        tool: 'Grok 生成中',
        thought: null
      });
      if (reports.length >= 3) break;
    } else if (!idle) {
      idle = {
        ...base,
        id: 'grok',
        status: activity,
        tool: activity === 'done' ? '本轮完成' : '空闲'
      };
    }
  }
  if (reports.length > 0) return reports;
  return idle ? [idle] : [];
}

// MARK: Hermes

const HERMES_DB_NAME = 'state.db';

function hermesProcessRunning() {
  if (pgrep('/Applications/Hermes.app/Contents/MacOS/')) return true;
  const exact = spawnSync('/usr/bin/pgrep', ['-x', 'hermes'], { encoding: 'utf8' });
  if (exact.status === 0) return true;
  const gateway = spawnSync('/usr/bin/pgrep', ['-f', 'hermes gateway'], { encoding: 'utf8' });
  return gateway.status === 0;
}

function hermesHome() {
  return process.env.HERMES_HOME || path.join(HOME, '.hermes');
}

function hermesReports() {
  if (!hermesProcessRunning()) return [];
  const db = path.join(hermesHome(), HERMES_DB_NAME);
  if (!fs.existsSync(db)) return [];
  const sessionInfo = sqliteJSON(db, 'PRAGMA table_info(sessions)');
  const sessionSQL = hermesSessionSelect(sessionInfo.map((row) => row && row.name).filter((name) => typeof name === 'string'));
  if (!sessionSQL) return [];
  const sessionRows = sqliteJSON(db, sessionSQL).map(normalizeHermesSession).filter(Boolean);
  const messageInfo = sqliteJSON(db, 'PRAGMA table_info(messages)');
  const messageSQL = hermesMessageSelect(
    messageInfo.map((row) => row && row.name).filter((name) => typeof name === 'string'),
    sessionRows.map((session) => session.id)
  );
  const messages = messageSQL ? latestHermesMessages(sqliteJSON(db, messageSQL)) : {};
  const now = Date.now();
  const running = inferHermesRunning(sessionRows, messages, now, 3);
  return running.length > 0 ? running : [hermesIdleReport(sessionRows, now, messages)];
}

// MARK: main

function tick() {
  const adapters = [
    { group: 'codex', name: 'Codex', bundleID: 'com.openai.codex', reports: codexReports },
    { group: 'workbuddy', name: 'WorkBuddy', bundleID: 'com.tencent.workbuddy.mac', reports: workbuddyReports },
    { group: 'grok', name: 'Grok Bot', bundleID: 'com.anysphere.sand', reports: grokReports },
    { group: 'hermes', name: 'Hermes', bundleID: null, reports: hermesReports }
  ];
  const all = [];
  for (const adapter of adapters) {
    let reports = [];
    try {
      reports = adapter.reports();
    } catch (error) {
      console.error(new Date().toISOString(), adapter.group, 'error:', error.message);
    }
    const parent = aggregateApp(adapter, reports);
    if (!once) syncGroup(adapter.group, parent ? [parent] : []);
    if (parent) all.push(parent);
  }
  if (once) {
    console.log(JSON.stringify(all, null, 2));
    return;
  }
  const key = all.map((report) => report.id + ':' + report.status + ':' + (report.tool || '')).join(' ');
  if (key !== tick.lastKey || Date.now() - (tick.lastAt || 0) > 60000) {
    console.log(new Date().toISOString(), key || 'none');
    tick.lastKey = key;
    tick.lastAt = Date.now();
  }
  if (agentBarRunning()) {
    appGoneSince = 0;
  } else {
    if (!appGoneSince) appGoneSince = Date.now();
    if (Date.now() - appGoneSince > 20000) {
      console.log(new Date().toISOString(), 'Agent Bar not running; adapter exiting');
      shutdown(0);
    }
  }
}

if (!once) {
  if (!acquireLock()) {
    console.log(new Date().toISOString(), 'another adapter watcher is already running; exiting');
    process.exit(0);
  }
  cleanupOwnReports();
}
tick();
if (!once) setInterval(tick, TICK_MS);
