import test from 'node:test';
import assert from 'node:assert/strict';
import {
  claudeApprovalCommand, claudeApprovalToolAllowed, claudeApprovalOutput,
  claudeApprovalDecision, claudeHeartbeatFresh, claudePendingExpired,
  claudeDecisionExpired, claudeApprovalRequest
} from '../tools/lib/claude-approval-logic.mjs';

test('Bash keeps the command and caps it at 4000 characters', () => {
  assert.equal(claudeApprovalCommand('Bash', { command: 'rm -rf build' }), 'rm -rf build');
  const long = 'x'.repeat(5000);
  assert.equal(claudeApprovalCommand('Bash', { command: long }).length, 4001); // 4000 + '…'
});

test('Edit falls back to file_path, unknown tools serialize the input', () => {
  assert.equal(claudeApprovalCommand('Edit', { file_path: '/tmp/a.txt', old_string: 'a' }), '/tmp/a.txt');
  assert.match(claudeApprovalCommand('WebFetch', { url: 'https://example.com' }), /example\.com/);
});

test('tool regex is anchored by the caller', () => {
  assert.equal(claudeApprovalToolAllowed('Bash'), true);
  assert.equal(claudeApprovalToolAllowed('BashFoo'), false);
  assert.equal(claudeApprovalToolAllowed('Edit'), false);
  assert.equal(claudeApprovalToolAllowed('Edit', '^Bash$|^Edit$'), true);
  assert.equal(claudeApprovalToolAllowed('Edit', '('), false);
});

test('allow output uses the PermissionRequest shape', () => {
  assert.deepEqual(claudeApprovalOutput('allow'), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } }
  });
});

test('deny output carries the message', () => {
  assert.deepEqual(claudeApprovalOutput('deny', 'no'), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'deny', message: 'no' } }
  });
});

test('decision requires matching id and nonce', () => {
  const expected = { id: 'a', nonce: 'n' };
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'n', decision: 'allow' }, expected), 'allow');
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'n', decision: 'deny' }, expected), 'deny');
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'b', nonce: 'n', decision: 'allow' }, expected), null);
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'x', decision: 'allow' }, expected), null);
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'n', decision: 'maybe' }, expected), null);
  assert.equal(claudeApprovalDecision(null, expected), null);
});

test('heartbeat and expiry bounds', () => {
  assert.equal(claudeHeartbeatFresh(1000, 10_000), true);
  assert.equal(claudeHeartbeatFresh(1000, 11_001), false);
  assert.equal(claudePendingExpired(0, 119_999), false);
  assert.equal(claudePendingExpired(0, 120_001), true);
  assert.equal(claudeDecisionExpired(0, 599_999), false);
  assert.equal(claudeDecisionExpired(0, 600_001), true);
});

test('request is built only for PermissionRequest events', () => {
  const base = {
    hook_event_name: 'PermissionRequest', session_id: 's1', cwd: '/Users/x/proj',
    tool_name: 'Bash', tool_input: { command: 'ls' }
  };
  const request = claudeApprovalRequest(base, { now: 123, id: 'id1', nonce: 'n1' });
  assert.deepEqual(request, {
    schema: 1, id: 'id1', nonce: 'n1', sessionId: 's1', cwd: '/Users/x/proj',
    tool: 'Bash', command: 'ls', createdAt: 123
  });
  assert.equal(claudeApprovalRequest({ ...base, hook_event_name: 'PreToolUse' }, { now: 1, id: 'i', nonce: 'n' }), null);
  assert.equal(claudeApprovalRequest({ ...base, session_id: '' }, { now: 1, id: 'i', nonce: 'n' }), null);
});
