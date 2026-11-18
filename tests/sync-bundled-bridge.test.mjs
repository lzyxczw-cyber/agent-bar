import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SYNC = path.join(ROOT, 'tools', 'sync-bundled-bridge.sh');

function runSync(source, destination) {
  return spawnSync('bash', [SYNC, source, destination], { encoding: 'utf8' });
}

function writeTree(dir, files) {
  for (const [rel, contents] of Object.entries(files)) {
    const file = path.join(dir, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, contents);
  }
}

function makeSource(root) {
  const source = path.join(root, 'bridge');
  writeTree(source, {
    'dsh-bridge.mjs': 'export const build = 1;\n',
    'README.md': '# bridge\n',
    'lib/dsh-auth.mjs': 'export const auth = true;\n',
    'lib/nested/keep.mjs': 'export const nested = true;\n',
    'lib/usage.mjs': 'export const usage = 1;\n',
    'vendor/ws-mux.mjs': 'export const mux = true;\n',
    'tools/probe.mjs': 'should-not-ship\n',
    'status.json': '{"from":"source"}\n',
    'audit.log': 'source-audit\n',
    'usage-state.json': '{"from":"source"}\n',
    'control/token': 'source-token\n',
    'control/request-old.json': '{"from":"source"}\n'
  });
  return source;
}

function runtimeSnapshot(dir) {
  const names = [
    'status.json',
    'audit.log',
    'usage-state.json',
    'control/token',
    'control/request-live.json',
    'notes.txt'
  ];
  const snap = {};
  for (const name of names) {
    const file = path.join(dir, name);
    snap[name] = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
  }
  return snap;
}

test('fresh install writes the program and skips dev tools and generated files', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agentbar-sync-fresh-'));
  const source = makeSource(root);
  const dest = path.join(root, 'Application Support', 'AgentBar', 'bridge');
  const result = runSync(source, dest);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(dest, 'dsh-bridge.mjs'), 'utf8'), 'export const build = 1;\n');
  assert.equal(fs.readFileSync(path.join(dest, 'lib', 'dsh-auth.mjs'), 'utf8'), 'export const auth = true;\n');
  assert.equal(fs.readFileSync(path.join(dest, 'lib', 'nested', 'keep.mjs'), 'utf8'), 'export const nested = true;\n');
  assert.equal(fs.readFileSync(path.join(dest, 'vendor', 'ws-mux.mjs'), 'utf8'), 'export const mux = true;\n');
  assert.equal(fs.readFileSync(path.join(dest, 'README.md'), 'utf8'), '# bridge\n');
  assert.equal(fs.existsSync(path.join(dest, 'tools')), false);
  assert.equal(fs.existsSync(path.join(dest, 'status.json')), false);
  assert.equal(fs.existsSync(path.join(dest, 'audit.log')), false);
  assert.equal(fs.existsSync(path.join(dest, 'usage-state.json')), false);
  assert.equal(fs.existsSync(path.join(dest, 'control')), false);
});

test('refresh replaces program files and keeps live runtime state', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agentbar-sync-keep-'));
  const source = makeSource(root);
  const dest = path.join(root, 'Application Support', 'AgentBar', 'bridge');
  writeTree(dest, {
    'dsh-bridge.mjs': 'old\n',
    'lib/stale.mjs': 'remove-me\n',
    'lib/dsh-auth.mjs': 'old-auth\n',
    'vendor/ws-mux.mjs': 'old-mux\n',
    'status.json': '{"bridge":{"pid":4242}}\n',
    'audit.log': 'kept-audit\n',
    'usage-state.json': '{"tokensToday":9}\n',
    'control/token': 'live-token\n',
    'control/request-live.json': '{"approvalId":"a1"}\n',
    'notes.txt': 'leave-this\n'
  });
  const sockPath = path.join(dest, 'status.sock');
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(sockPath, resolve);
  });
  const before = runtimeSnapshot(dest);
  const tokenMtime = fs.statSync(path.join(dest, 'control', 'token')).mtimeMs;

  const result = runSync(source, dest);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(dest, 'dsh-bridge.mjs'), 'utf8'), 'export const build = 1;\n');
  assert.equal(fs.existsSync(path.join(dest, 'lib', 'stale.mjs')), false);
  assert.equal(fs.readFileSync(path.join(dest, 'lib', 'usage.mjs'), 'utf8'), 'export const usage = 1;\n');
  assert.deepEqual(runtimeSnapshot(dest), before);
  assert.equal(fs.statSync(path.join(dest, 'control', 'token')).mtimeMs, tokenMtime);
  assert.equal(fs.statSync(sockPath).isSocket(), true);
  server.close();
});

test('a second sync picks up a changed program without rewriting runtime files', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agentbar-sync-again-'));
  const source = makeSource(root);
  const dest = path.join(root, 'dest');
  writeTree(dest, {
    'status.json': 'live\n',
    'control/token': 'tok\n',
    'audit.log': 'audit\n',
    'usage-state.json': 'usage\n'
  });
  assert.equal(runSync(source, dest).status, 0);
  fs.writeFileSync(path.join(source, 'dsh-bridge.mjs'), 'export const build = 2;\n');
  fs.writeFileSync(path.join(source, 'status.json'), 'source-changed\n');
  const result = runSync(source, dest);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(dest, 'dsh-bridge.mjs'), 'utf8'), 'export const build = 2;\n');
  assert.equal(fs.readFileSync(path.join(dest, 'status.json'), 'utf8'), 'live\n');
  assert.equal(fs.readFileSync(path.join(dest, 'control', 'token'), 'utf8'), 'tok\n');
  assert.equal(fs.readFileSync(path.join(dest, 'audit.log'), 'utf8'), 'audit\n');
  assert.equal(fs.readFileSync(path.join(dest, 'usage-state.json'), 'utf8'), 'usage\n');
});

test('an incomplete bundle fails before touching the destination', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agentbar-sync-bad-'));
  const source = makeSource(root);
  fs.rmSync(path.join(source, 'dsh-bridge.mjs'));
  const dest = path.join(root, 'dest');
  writeTree(dest, {
    'status.json': 'live\n',
    'lib/dsh-auth.mjs': 'keep\n',
    'control/token': 'tok\n'
  });
  const result = runSync(source, dest);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /incomplete/);
  assert.equal(fs.readFileSync(path.join(dest, 'status.json'), 'utf8'), 'live\n');
  assert.equal(fs.readFileSync(path.join(dest, 'lib', 'dsh-auth.mjs'), 'utf8'), 'keep\n');
  assert.equal(fs.readFileSync(path.join(dest, 'control', 'token'), 'utf8'), 'tok\n');
});

test('refuses to sync a directory onto itself', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agentbar-sync-same-'));
  const source = makeSource(root);
  const result = runSync(source, source);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /itself/);
  assert.equal(fs.readFileSync(path.join(source, 'lib', 'dsh-auth.mjs'), 'utf8'), 'export const auth = true;\n');
  assert.equal(fs.readFileSync(path.join(source, 'status.json'), 'utf8'), '{"from":"source"}\n');
});

test('usage without two paths exits 2', () => {
  const result = spawnSync('bash', [SYNC], { encoding: 'utf8' });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /usage:/);
});

test('the real bridge tree syncs with every relative import resolvable', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agentbar-sync-real-'));
  const dest = path.join(root, 'Library', 'Application Support', 'AgentBar', 'bridge');
  writeTree(dest, {
    'status.json': '{"ok":true}\n',
    'audit.log': 'audit\n',
    'usage-state.json': '{}\n',
    'control/token': 'secret\n'
  });
  const result = runSync(path.join(ROOT, 'bridge'), dest);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.existsSync(path.join(dest, 'dsh-bridge.mjs')), true);
  assert.equal(fs.existsSync(path.join(dest, 'lib', 'dsh-auth.mjs')), true);
  assert.equal(fs.existsSync(path.join(dest, 'lib', 'questions.mjs')), true);
  assert.equal(fs.existsSync(path.join(dest, 'vendor', 'ws-mux.mjs')), true);
  assert.equal(fs.existsSync(path.join(dest, 'tools')), false);
  assert.equal(fs.readFileSync(path.join(dest, 'status.json'), 'utf8'), '{"ok":true}\n');
  assert.equal(fs.readFileSync(path.join(dest, 'control', 'token'), 'utf8'), 'secret\n');
  assert.equal(fs.readFileSync(path.join(dest, 'audit.log'), 'utf8'), 'audit\n');
  assert.equal(fs.readFileSync(path.join(dest, 'usage-state.json'), 'utf8'), '{}\n');

  const programFiles = [];
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      const file = path.join(dir, name);
      if (fs.statSync(file).isDirectory()) walk(file);
      else if (name.endsWith('.mjs')) programFiles.push(file);
    }
  };
  walk(dest);
  const importPattern = /from\s+['"](\.[^'"]+)['"]/g;
  assert.ok(programFiles.length >= 3);
  for (const file of programFiles) {
    const text = fs.readFileSync(file, 'utf8');
    for (const match of text.matchAll(importPattern)) {
      const resolved = path.resolve(path.dirname(file), match[1]);
      assert.equal(fs.existsSync(resolved), true, `${file} imports missing ${match[1]}`);
    }
  }
});

test('build.sh and start.sh both install through the sync script', () => {
  const build = fs.readFileSync(path.join(ROOT, 'build.sh'), 'utf8');
  const start = fs.readFileSync(path.join(ROOT, 'start.sh'), 'utf8');
  assert.match(build, /sync-bundled-bridge\.sh bridge "\$APP\/Contents\/Resources\/bridge"/);
  assert.match(build, /Contents\/Resources\/tools\/sync-bundled-bridge\.sh/);
  assert.match(start, /sync-bundled-bridge\.sh "\$PWD\/bridge" "\$BRIDGE_DEST"/);
  assert.doesNotMatch(start, /rm\s+.*usage-state\.json/);
  assert.doesNotMatch(start, /rm\s+.*audit\.log/);
  assert.doesNotMatch(start, /rm\s+.*control/);
});
