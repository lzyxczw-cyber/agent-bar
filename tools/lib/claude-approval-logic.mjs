/**
 * claude-approval-logic.mjs — pure helpers for Agent Bar's Claude Code
 * PermissionRequest approval hook. No file I/O, no side effects.
 *
 * The hook (tools/agentbar-claude-approve.mjs) owns the files; this module
 * only decides what to write and what a decision means, so both can be
 * unit-tested without a running App.
 */

export const CLAUDE_APPROVAL_HEARTBEAT_MS = 10_000;
export const CLAUDE_APPROVAL_PENDING_MS = 120_000;
export const CLAUDE_APPROVAL_DECISION_MS = 600_000;
export const CLAUDE_APPROVAL_WAIT_MS = 40_000;
export const CLAUDE_APPROVAL_POLL_MS = 150;
export const CLAUDE_APPROVAL_COMMAND_MAX = 4000;

function compact (value) {
  return String(value ?? '').replace(/\r\n?/g, '\n').trim();
}

/** A human-readable description of the tool call shown in the panel. */
export function claudeApprovalCommand (toolName, toolInput) {
  const input = toolInput && typeof toolInput === 'object' ? toolInput : {};
  let text = '';
  if (typeof input.command === 'string') text = input.command;
  else if (typeof input.file_path === 'string') text = input.file_path;
  else {
    try { text = JSON.stringify (input); } catch { text = ''; }
  }
  text = compact (text);
  if (text.length <= CLAUDE_APPROVAL_COMMAND_MAX) return text;
  return text.slice (0, CLAUDE_APPROVAL_COMMAND_MAX) + '…';
}

/** The matcher is a regex; an invalid pattern means "not allowed". */
export function claudeApprovalToolAllowed (toolName, pattern = '^Bash$') {
  if (typeof toolName !== 'string' || toolName === '') return false;
  try {
    return new RegExp (pattern).test (toolName);
  } catch {
    return false;
  }
}

/** The PermissionRequest hook output object. */
export function claudeApprovalOutput (behavior, message) {
  const decision = behavior === 'deny'
    ? { behavior: 'deny', message: message || 'Agent Bar 面板已拒绝' }
    : { behavior: 'allow' };
  return { hookSpecificOutput: { hookEventName: 'PermissionRequest', decision } };
}

/** Validate a decision file against this hook's id and nonce. */
export function claudeApprovalDecision (payload, expected) {
  if (!payload || typeof payload !== 'object' || Array.isArray (payload)) return null;
  if (payload.schema !== 1) return null;
  if (!expected || payload.id !== expected.id || payload.nonce !== expected.nonce) return null;
  if (payload.decision === 'allow' || payload.decision === 'deny') return payload.decision;
  return null;
}

export function claudeHeartbeatFresh (mtimeMs, now) {
  return Number.isFinite (mtimeMs) && Number (now) - mtimeMs <= CLAUDE_APPROVAL_HEARTBEAT_MS;
}

export function claudePendingExpired (createdAt, now) {
  return !Number.isFinite (createdAt) || Number (now) - createdAt > CLAUDE_APPROVAL_PENDING_MS;
}

export function claudeDecisionExpired (decidedAt, now) {
  return !Number.isFinite (decidedAt) || Number (now) - decidedAt > CLAUDE_APPROVAL_DECISION_MS;
}

/** Build the pending request, or null when this event is not ours to ask. */
export function claudeApprovalRequest (input, options) {
  if (!input || typeof input !== 'object') return null;
  if (input.hook_event_name !== 'PermissionRequest') return null;
  if (typeof input.session_id !== 'string' || input.session_id === '') return null;
  if (typeof input.tool_name !== 'string' || input.tool_name === '') return null;
  if (!options || !options.id || !options.nonce) return null;
  return {
    schema: 1,
    id: options.id,
    nonce: options.nonce,
    sessionId: input.session_id,
    cwd: typeof input.cwd === 'string' ? input.cwd : '',
    tool: input.tool_name,
    command: claudeApprovalCommand (input.tool_name, input.tool_input),
    createdAt: options.now
  };
}
