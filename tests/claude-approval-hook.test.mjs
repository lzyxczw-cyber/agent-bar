import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const HOOK = path.join(ROOT, 'tools', 'agentbar-claude-approve.mjs');

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-approve-'));
  fs.mkdirSync(path.join(dir, 'pending'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'decisions'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'heartbeat'), '');
  return dir;
}

function startHook(dir, input, env = {}) {
  const child = spawn(process.execPath, [HOOK], {
    env: { ...process.env, AGENTBAR_CLAUDE_APPROVAL_DIR: dir, ...env }
  });
  child.stdin.end(JSON.stringify(input));
  let stdout = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  const done = new Promise((resolve) => child.on('close', (code) => resolve({ code, stdout })));
  return { child, done };
}

async function waitFor(fn, timeout = 5000) {
  const started = Date.now();
  for (;;) {
    const value = fn();
    if (value) return value;
    if (Date.now() - started > timeout) throw new Error('waitFor timed out');
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

async function respond(dir, decision, mutate = (payload) => payload) {
  const name = await waitFor(() => fs.readdirSync(path.join(dir, 'pending')).find((n) => n.endsWith('.json')));
  const request = JSON.parse(fs.readFileSync(path.join(dir, 'pending', name), 'utf8'));
  const payload = mutate({ schema: 1, id: request.id, nonce: request.nonce, decision, decidedAt: Date.now() });
  fs.writeFileSync(path.join(dir, 'decisions', request.id + '.json'), JSON.stringify(payload));
  return request;
}

const INPUT = {
  hook_event_name: 'PermissionRequest', session_id: 's1', cwd: '/tmp/p',
  tool_name: 'Bash', tool_input: { command: 'rm -rf build' }
};

test('allow is returned in the PermissionRequest shape and files are cleaned', async () => {
  const dir = tempDir();
  const { done } = startHook(dir, INPUT);
  const request = await respond(dir, 'allow');
  const result = await done;
  assert.equal(result.code, 0);
  assert.deepEqual(JSON.parse(result.stdout).hookSpecificOutput.decision, { behavior: 'allow' });
  assert.equal(request.command, 'rm -rf build');
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0);
  assert.equal(fs.readdirSync(path.join(dir, 'decisions')).length, 0);
});

test('deny carries the rejection message', async () => {
  const dir = tempDir();
  const { done } = startHook(dir, INPUT);
  await respond(dir, 'deny');
  const result = await done;
  const decision = JSON.parse(result.stdout).hookSpecificOutput.decision;
  assert.equal(decision.behavior, 'deny');
  assert.match(decision.message, /拒绝/);
});

test('a wrong nonce is ignored and the hook times out silently', async () => {
  const dir = tempDir();
  const { done } = startHook(dir, INPUT, { AGENTBAR_CLAUDE_APPROVAL_WAIT_MS: '600', AGENTBAR_CLAUDE_APPROVAL_POLL_MS: '30' });
  await respond(dir, 'allow', (payload) => ({ ...payload, nonce: 'forged' }));
  const result = await done;
  assert.equal(result.code, 0);
  assert.equal(result.stdout, '');
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0); // timeout cleans up
});

test('a stale heartbeat exits without asking', async () => {
  const dir = tempDir();
  const old = new Date(Date.now() - 60_000);
  fs.utimesSync(path.join(dir, 'heartbeat'), old, old);
  const started = Date.now();
  const { done } = startHook(dir, INPUT);
  const result = await done;
  assert.equal(result.code, 0);
  assert.equal(result.stdout, '');
  assert.ok(Date.now() - started < 2000);
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0);
});

test('other hook events and non-matching tools do nothing', async () => {
  const dir = tempDir();
  for (const input of [
    { ...INPUT, hook_event_name: 'PreToolUse' },
    { ...INPUT, tool_name: 'Read', tool_input: { file_path: '/tmp/a' } }
  ]) {
    const { done } = startHook(dir, input);
    const result = await done;
    assert.equal(result.code, 0);
    assert.equal(result.stdout, '');
  }
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0);
});

test('a missing approval directory exits silently', async () => {
  const dir = path.join(os.tmpdir(), 'ab-approve-missing-' + Date.now());
  const { done } = startHook(dir, INPUT);
  const result = await done;
  assert.equal(result.code, 0);
  assert.equal(result.stdout, '');
});
