/**
 * Pure helpers for desktop-app adapters.
 * Status is inferred from local files. There is no official API.
 */

export function hermesTimestampMs (value) {
  const number = Number (value);
  if (!Number.isFinite (number) || number <= 0) return null;
  if (number < 1e12) return Math.round (number * 1000);
  return Math.round (number);
}

const SESSION_COLUMNS = ['id', 'title', 'source', 'cwd', 'started_at', 'ended_at', 'input_tokens', 'output_tokens'];
const MESSAGE_COLUMNS = ['session_id', 'role', 'content', 'tool_name', 'timestamp', 'reasoning', 'reasoning_content'];

function selectedColumns (present, allowed) {
  const have = new Set (present);
  return allowed.filter ((name) => have.has (name));
}

/** Null when the sessions table is missing the columns this adapter understands. */
export function hermesSessionSelect (presentColumns) {
  const columns = selectedColumns (presentColumns, SESSION_COLUMNS);
  if (!columns.includes ('id') || !columns.includes ('started_at') || !columns.includes ('ended_at')) return null;
  return 'SELECT ' + columns.join (', ') + ' FROM sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 12';
}

export function hermesMessageSelect (presentColumns, sessionIds) {
  const columns = selectedColumns (presentColumns, MESSAGE_COLUMNS);
  if (!columns.includes ('session_id') || !columns.includes ('timestamp')) return null;
  const ids = (sessionIds || []).filter ((id) => typeof id === 'string' && /^[A-Za-z0-9_.:-]{1,80}$/.test (id));
  if (ids.length === 0) return null;
  const list = ids.map ((id) => "'" + id + "'").join (', ');
  return 'SELECT ' + columns.join (', ') + ' FROM messages WHERE session_id IN (' + list + ') ORDER BY timestamp DESC LIMIT 80';
}

export function normalizeHermesSession (row) {
  if (!row || typeof row !== 'object' || row.id == null || String (row.id) === '') return null;
  const ended = row.ended_at == null || row.ended_at === '' ? null : hermesTimestampMs (row.ended_at);
  return {
    id: String (row.id),
    title: row.title == null || String (row.title).trim () === '' ? null : String (row.title),
    source: row.source == null ? null : String (row.source),
    cwd: row.cwd == null || String (row.cwd).trim () === '' ? null : String (row.cwd),
    startedAt: hermesTimestampMs (row.started_at),
    endedAt: ended
  };
}

export function latestHermesMessages (rows) {
  const bySession = {};
  for (const row of rows || []) {
    if (!row || row.session_id == null) continue;
    const id = String (row.session_id);
    const at = hermesTimestampMs (row.timestamp);
    if (at == null) continue;
    const current = bySession[id];
    if (current && current.at > at) continue;
    const reasoning = typeof row.reasoning === 'string' && row.reasoning.trim () !== ''
      ? row.reasoning
      : (typeof row.reasoning_content === 'string' ? row.reasoning_content : null);
    const content = typeof row.content === 'string' ? row.content : null;
    bySession[id] = {
      at,
      role: row.role == null ? null : String (row.role),
      tool: row.tool_name == null || String (row.tool_name).trim () === '' ? null : String (row.tool_name),
      text: (reasoning && reasoning.trim ()) || (content && content.trim ()) || null
    };
  }
  return bySession;
}

function projectFor (session) {
  if (session.cwd) {
    const parts = String (session.cwd).split (/[/\\]/).filter (Boolean);
    if (parts.length > 0) return parts[parts.length - 1];
  }
  return session.title || 'Hermes';
}

function compact (value, limit) {
  if (value == null) return null;
  const text = String (value).replace (/\s+/g, ' ').trim ();
  if (!text) return null;
  return text.length > limit ? text.slice (0, limit) + '…' : text;
}

/**
 * Open sessions whose latest message is within `runningMs` (default 90s).
 * At most `limit` sessions, newest activity first. Ended or stale sessions are omitted.
 */
export function inferHermesRunning (sessions, messagesById, now, limit = 3, runningMs = 90 * 1000) {
  const reports = [];
  for (const session of sessions || []) {
    if (!session || !session.id || session.endedAt != null) continue;
    const message = messagesById ? messagesById[session.id] : null;
    if (!message || typeof message.at !== 'number') continue;
    if (now - message.at > runningMs || now < message.at) continue;
    const tool = message.tool
      ? message.tool
      : (message.role === 'assistant' ? '回复' : (message.role === 'user' ? '等待回复' : '活动'));
    reports.push ({
      id: 'hermes-' + session.id.slice (0, 8),
      name: 'Hermes',
      status: 'running',
      project: projectFor (session),
      tool,
      thought: compact (message.text, 600),
      startedAt: session.startedAt || message.at,
      updatedAt: message.at
    });
  }
  reports.sort ((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
  return reports.slice (0, Math.max (0, limit));
}

export function hermesIdleReport (sessions, now) {
  const open = (sessions || []).filter ((session) => session && session.id && session.endedAt == null);
  open.sort ((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
  const newest = open[0] || null;
  return {
    id: 'hermes',
    name: 'Hermes',
    status: 'done',
    project: newest ? projectFor (newest) : 'Hermes',
    tool: '空闲',
    thought: null,
    startedAt: newest && newest.startedAt ? newest.startedAt : now,
    updatedAt: now
  };
}

/**
 * One parent row per desktop app. Active children are capped at 3.
 * This is the same fold the watcher uses before it writes a report file.
 */
export function aggregateApp (adapter, reports) {
  const active = (reports || [])
    .filter ((report) => report && report.status === 'running' && report.id !== adapter.group)
    .sort ((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
  const idle = (reports || []).find ((report) => report && report.id === adapter.group) || (reports || [])[0] || null;
  if (active.length === 0) {
    if (!idle) return null;
    return {
      id: adapter.group,
      name: adapter.name,
      status: 'done',
      project: idle.project || adapter.name,
      tool: idle.tool || '空闲',
      detail: idle.detail || null,
      thought: idle.thought || null,
      startedAt: idle.startedAt || 0,
      tokens: idle.tokens || null,
      appBundleID: adapter.bundleID || null,
      sessions: []
    };
  }
  const latest = active[0];
  const sessions = active.slice (0, 3).map ((report) => ({
    id: report.id,
    project: report.project || adapter.name,
    tool: report.tool || null,
    detail: report.detail || null,
    status: report.status,
    startedAt: report.startedAt || 0,
    updatedAt: report.updatedAt || report.startedAt || 0,
    thought: report.thought || null,
    tokens: report.tokens || null
  }));
  const startedAt = Math.min (...active.map ((report) => report.startedAt || 0));
  const tokens = active.reduce ((sum, report) => sum + (Number (report.tokens) || 0), 0);
  return {
    id: adapter.group,
    name: adapter.name,
    status: 'running',
    project: latest.project || adapter.name,
    tool: latest.tool || '运行中',
    detail: latest.detail || null,
    thought: latest.thought || null,
    startedAt,
    tokens: tokens || null,
    appBundleID: adapter.bundleID || null,
    sessions,
    process: latest.process || []
  };
}
