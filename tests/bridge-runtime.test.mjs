import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BRIDGE = path.join(ROOT, 'bridge', 'dsh-bridge.mjs');

// macOS caps Unix socket paths at 104 bytes, so keep this test's tree short.
function shortTempRoot(prefix) {
  const base = fs.existsSync('/tmp') ? '/tmp' : os.tmpdir();
  return fs.mkdtempSync(path.join(base, prefix));
}

async function waitFor(predicate, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('timed out after ' + timeoutMs + 'ms');
}

// Regression: startSocket used to await a promise that never settled when the
// bind failed, so main() never reached scheduleTick and status.json was never
// written. A bad socket path must degrade the socket, not kill the feed.
test('a status socket that cannot bind does not stall the feed', async () => {
  const root = shortTempRoot('ab-sock-');
  const out = path.join(root, 'status.json');
  const child = spawn(process.execPath, [
    BRIDGE,
    '--no-ws',
    '--no-translate',
    '--no-external',
    '--url', 'http://127.0.0.1:1',
    '--interval', '250',
    '--out', out,
    '--socket', path.join(root, 's'.repeat(110) + '.sock'),
    '--control-dir', path.join(root, 'control'),
    '--agents-dir', path.join(root, 'agents')
  ], { stdio: ['ignore', 'pipe', 'pipe'] });

  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk; });
  child.stderr.on('data', (chunk) => { output += chunk; });

  try {
    await waitFor(() => fs.existsSync(out), 15000);
    const snapshot = JSON.parse(fs.readFileSync(out, 'utf8'));
    assert.equal(snapshot.schema, 1);
    assert.equal(typeof snapshot.ts, 'number');
    assert.match(output, /socket unavailable/);
  } finally {
    child.kill('SIGTERM');
  }
});
