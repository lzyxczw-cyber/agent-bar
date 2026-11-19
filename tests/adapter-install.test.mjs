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

test('claude install writes the approval hook and copies the scripts', () => {
  const home = tempHome();
  const settings = path.join(home, '.claude', 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({ permissions: { allow: [] } }, null, 2) + '\n');

  const installed = run(home, 'claude');
  assert.equal(installed.status, 0, installed.stderr);
  const hooks = JSON.parse(fs.readFileSync(settings, 'utf8')).hooks;
  assert.equal(hooks.PermissionRequest.length, 1);
  assert.equal(hooks.PermissionRequest[0].matcher, '^Bash$');
  const hook = hooks.PermissionRequest[0].hooks[0];
  assert.equal(hook.timeout, 45);
  assert.match(hook.command, /agentbar-claude-approve\.mjs/);
  assert.ok(fs.existsSync(path.join(home, 'Library', 'Application Support', 'AgentBar', 'hooks', 'agentbar-claude-approve.mjs')));
  assert.ok(fs.existsSync(path.join(home, 'Library', 'Application Support', 'AgentBar', 'hooks', 'lib', 'claude-approval-logic.mjs')));
});

test('installing twice does not duplicate the hook and can override the matcher', () => {
  const home = tempHome();
  run(home, 'claude');
  run(home, 'claude', '--tools', '^Bash$|^Edit$');
  const hooks = JSON.parse(fs.readFileSync(path.join(home, '.claude', 'settings.json'), 'utf8')).hooks;
  assert.equal(hooks.PermissionRequest.length, 1);
  assert.match(hooks.PermissionRequest[0].matcher, /Edit/);
});

test('claude install honors CLAUDE_CONFIG_DIR and removes legacy report hooks', () => {
  const home = tempHome();
  const config = path.join(home, 'alt-claude');
  fs.mkdirSync(config, { recursive: true });
  const settings = path.join(config, 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({
    hooks: { PreToolUse: [{ hooks: [{ type: 'command', command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }] }
  }, null, 2) + '\n');

  const result = spawnSync(process.execPath, [INSTALLER, 'claude'], {
    encoding: 'utf8',
    env: { ...process.env, HOME: home, CLAUDE_CONFIG_DIR: config }
  });
  assert.equal(result.status, 0, result.stderr);
  const node = JSON.parse(fs.readFileSync(settings, 'utf8'));
  assert.equal(node.hooks.PreToolUse, undefined);
  assert.equal(node.hooks.PermissionRequest.length, 1);
});

test('uninstall removes both hook generations and the copied scripts', () => {
  const home = tempHome();
  run(home, 'claude');
  const settings = path.join(home, '.claude', 'settings.json');
  const node = JSON.parse(fs.readFileSync(settings, 'utf8'));
  node.hooks.PreToolUse = [{ hooks: [{ type: 'command', command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }];
  fs.writeFileSync(settings, JSON.stringify(node, null, 2) + '\n');

  const removed = run(home, 'uninstall-claude');
  assert.equal(removed.status, 0, removed.stderr);
  assert.equal(JSON.parse(fs.readFileSync(settings, 'utf8')).hooks, undefined);
  assert.equal(fs.existsSync(path.join(home, 'Library', 'Application Support', 'AgentBar', 'hooks')), false);
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
  assert.match(base.stdout, /approval hook \(\^Bash\$\)/);
  assert.doesNotMatch(base.stdout, /Claude Code:\s+not installed/);

  const settings = path.join(home, '.claude', 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({
    hooks: { PreToolUse: [{ hooks: [{ command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }] }
  }, null, 2) + '\n');
  const legacy = run(home, 'status');
  assert.match(legacy.stdout, /1 legacy hook/);
});
