import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const INSTALLER = path.join(ROOT, 'tools', 'agentbar-install-adapter.mjs');

function run(home, ...args) {
  return spawnSync(process.execPath, [INSTALLER, ...args], {
    encoding: 'utf8',
    env: { ...process.env, HOME: home }
  });
}

function tempHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-install-'));
  fs.mkdirSync(path.join(home, '.claude'), { recursive: true });
  return home;
}

test('claude install only prints guidance and leaves settings untouched', () => {
  const home = tempHome();
  const settings = path.join(home, '.claude', 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({ permissions: { allow: [] } }, null, 2) + '\n');
  const before = fs.readFileSync(settings, 'utf8');

  const installed = run(home, 'claude');
  assert.equal(installed.status, 0, installed.stderr);
  assert.match(installed.stdout, /transcript/i);
  assert.equal(fs.readFileSync(settings, 'utf8'), before);
});

test('uninstall-claude still removes hooks installed by older versions', () => {
  const home = tempHome();
  const settings = path.join(home, '.claude', 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({
    hooks: {
      PreToolUse: [{ matcher: '*', hooks: [{ type: 'command', timeout: 5, command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }],
      Stop: [{ hooks: [{ type: 'command', timeout: 5, command: 'node /x/tools/agentbar-report.mjs --id claude-code --status done' }] }]
    }
  }, null, 2) + '\n');

  const removed = run(home, 'uninstall-claude');
  assert.equal(removed.status, 0, removed.stderr);
  assert.equal(JSON.parse(fs.readFileSync(settings, 'utf8')).hooks, undefined);
});

test('status reports transcript mode and calls out legacy hooks', () => {
  const home = tempHome();
  const base = run(home, 'status');
  assert.equal(base.status, 0, base.stderr);
  assert.match(base.stdout, /transcript/i);
  assert.doesNotMatch(base.stdout, /Claude Code:\s+not installed/);

  const settings = path.join(home, '.claude', 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({
    hooks: { PreToolUse: [{ hooks: [{ command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }] }
  }, null, 2) + '\n');
  const legacy = run(home, 'status');
  assert.match(legacy.stdout, /1 legacy hook/);
});
