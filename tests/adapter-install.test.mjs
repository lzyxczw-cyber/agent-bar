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

// Regression: removeOurHooks used to return the raw settings object when the
// file had no hooks key, so a first-time install crashed on `node.hooks`.
test('Claude adapter installs into a settings file without hooks, then uninstalls', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-install-'));
  const settings = path.join(home, '.claude', 'settings.json');

  const installed = run(home, 'claude');
  assert.equal(installed.status, 0, installed.stderr);
  const afterInstall = JSON.parse(fs.readFileSync(settings, 'utf8'));
  const hooks = Object.values(afterInstall.hooks || {}).flat().flatMap((group) => group.hooks || []);
  assert.equal(hooks.length, 2);
  for (const hook of hooks) {
    assert.equal(hook.type, 'command');
    assert.equal(hook.timeout, 5);
    assert.match(hook.command, /agentbar-report\.mjs/);
  }

  const removed = run(home, 'uninstall-claude');
  assert.equal(removed.status, 0, removed.stderr);
  const afterRemove = JSON.parse(fs.readFileSync(settings, 'utf8'));
  assert.equal(afterRemove.hooks, undefined);
});
