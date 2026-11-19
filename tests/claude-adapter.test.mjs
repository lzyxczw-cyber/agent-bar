import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ADAPTER = path.join(ROOT, 'tools', 'agentbar-app-adapters.mjs');

function fixtureHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-claude-'));
  fs.mkdirSync(path.join(home, '.claude', 'projects'), { recursive: true });
  return home;
}

function writeSession(home, project, id, lines) {
  const dir = path.join(home, '.claude', 'projects', project);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, id + '.jsonl');
  fs.writeFileSync(file, lines.map((line) => JSON.stringify(line)).join('\n') + '\n');
  return file;
}

function runOnce(home) {
  const result = spawnSync(process.execPath, [ADAPTER, '--once'], {
    encoding: 'utf8',
    env: { ...process.env, HOME: home, CLAUDE_CONFIG_DIR: path.join(home, '.claude') }
  });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test('three newest Claude sessions are reported, continued-in is skipped', () => {
  const home = fixtureHome();
  const now = Date.now();
  const assistant = (id, text, offset = 0) => ({
    type: 'assistant', sessionId: id, cwd: '/work/' + id, gitBranch: 'main',
    timestamp: new Date(now - offset).toISOString(),
    message: { id: 'msg-' + id, model: 'claude-x', stop_reason: 'tool_use', usage: { input_tokens: 1, output_tokens: 2 },
      content: [{ type: 'tool_use', name: 'Bash', input: { command: 'npm test' } }] }
  });
  writeSession(home, '-work-one', 'one', [assistant('one', 'a', 3000), { type: 'cost-state', sessionId: 'one' }]);
  writeSession(home, '-work-two', 'two', [assistant('two', 'b', 2000)]);
  writeSession(home, '-work-three', 'three', [assistant('three', 'c', 1000)]);
  writeSession(home, '-work-ghost', 'ghost', [
    { type: 'user', sessionId: 'ghost', timestamp: new Date(now - 500).toISOString(), message: { content: [{ type: 'tool_result' }] } },
    { type: 'continued-in', sessionId: 'ghost', timestamp: new Date(now).toISOString(), continuedInSessionId: 'three' }
  ]);
  fs.mkdirSync(path.join(home, '.claude', 'projects', '-work-one', 'tool-results'), { recursive: true });
  fs.writeFileSync(path.join(home, '.claude', 'projects', '-work-one', 'tool-results', 'ignored.jsonl'), '{}\n');

  const claude = runOnce(home).find((report) => report.id === 'claude');
  assert.ok(claude, 'claude parent report missing');
  assert.equal(claude.sessions.length, 3);
  assert.deepEqual(claude.sessions.map((s) => s.project).sort(), ['one', 'three', 'two']);
  assert.equal(claude.sessions[0].tool, 'Bash: npm test');
});

test('partial trailing line and missing directory do not break the watcher', () => {
  const home = fixtureHome();
  const file = writeSession(home, '-work-partial', 'partial', [{
    type: 'assistant', sessionId: 'partial', cwd: '/work/partial', timestamp: new Date().toISOString(),
    message: { id: 'm', model: 'claude-x', stop_reason: 'end_turn', usage: { output_tokens: 1 }, content: [{ type: 'text', text: 'done' }] }
  }]);
  fs.appendFileSync(file, '{"type":"assis');
  const claude = runOnce(home).find((report) => report.id === 'claude');
  assert.ok(claude);
  assert.equal(claude.status, 'done');

  const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-claude-empty-'));
  const output = runOnce(empty);
  assert.equal(output.some((report) => report.id === 'claude'), false);
});

test('transcripts untouched for the active window are not reported', () => {
  const home = fixtureHome();
  const file = writeSession(home, '-work-old', 'old', [{
    type: 'assistant', sessionId: 'old', cwd: '/work/old', timestamp: new Date().toISOString(),
    message: { id: 'm-old', model: 'claude-x', stop_reason: 'tool_use', usage: { output_tokens: 1 },
      content: [{ type: 'tool_use', name: 'Bash', input: { command: 'sleep 1' } }] }
  }]);
  const old = new Date(Date.now() - 20 * 60 * 1000);
  fs.utimesSync(file, old, old);
  const output = runOnce(home);
  assert.equal(output.some((report) => report.id === 'claude'), false);
});
