#!/usr/bin/env node
/**
 * agentbar-install-adapter.mjs — one-shot local adapters for Agent Bar.
 *
 *   node tools/agentbar-install-adapter.mjs claude
 *   node tools/agentbar-install-adapter.mjs codex
 *   node tools/agentbar-install-adapter.mjs status
 *   node tools/agentbar-install-adapter.mjs uninstall-claude
 *
 * Claude Code: merges PreToolUse/Stop hooks into ~/.claude/settings.json.
 * Codex: writes a heartbeat wrapper and prints the one-line alias to add.
 *
 * Only local files; never sends network requests.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const REPORT = path.join(TOOLS, 'agentbar-report.mjs');
const APP_SUPPORT = path.join(os.homedir(), 'Library', 'Application Support', 'AgentBar');
const ADAPTERS = path.join(APP_SUPPORT, 'adapters');
const CLAUDE_SETTINGS = path.join(os.homedir(), '.claude', 'settings.json');
const MARKER = 'agentbar-report.mjs';

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function backupFile(file) {
  if (!fs.existsSync(file)) return null;
  const backup = file + '.agentbar-backup-' + Date.now();
  fs.copyFileSync(file, backup);
  fs.chmodSync(backup, 0o600);
  return backup;
}

function readJSON(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function removeOurHooks(node) {
  let changed = false;
  const hooks = node && typeof node === 'object' ? node.hooks : null;
  if (!hooks || typeof hooks !== 'object') return { node, changed: false };
  for (const event of Object.keys(hooks)) {
    const groups = hooks[event];
    if (!Array.isArray(groups)) continue;
    const nextGroups = [];
    for (const group of groups) {
      if (!group || typeof group !== 'object' || !Array.isArray(group.hooks)) {
        nextGroups.push(group);
        continue;
      }
      const nextHooks = group.hooks.filter((hook) => {
        const command = hook && typeof hook.command === 'string' ? hook.command : '';
        return !command.includes(MARKER);
      });
      if (nextHooks.length !== group.hooks.length) changed = true;
      if (nextHooks.length > 0) nextGroups.push({ ...group, hooks: nextHooks });
    }
    if (nextGroups.length === 0) delete hooks[event];
    else hooks[event] = nextGroups;
  }
  if (Object.keys(hooks).length === 0) delete node.hooks;
  return { node, changed };
}

function installClaude() {
  const projects = path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'projects');
  console.log('Claude Code sessions are read directly from local transcripts under ' + projects + '; no hooks are needed.');
  console.log('If an older version installed hooks, run: node tools/agentbar-install-adapter.mjs uninstall-claude');
}

function uninstallClaude() {
  if (!fs.existsSync(CLAUDE_SETTINGS)) {
    console.log('No ' + CLAUDE_SETTINGS + ' found; nothing to remove.');
    return;
  }
  const node = readJSON(CLAUDE_SETTINGS, null);
  if (!node || typeof node !== 'object') throw new Error('cannot parse ' + CLAUDE_SETTINGS);
  const backup = backupFile(CLAUDE_SETTINGS);
  const result = removeOurHooks(node);
  fs.writeFileSync(CLAUDE_SETTINGS, JSON.stringify(result.node, null, 2) + '\n', { mode: 0o600 });
  fs.chmodSync(CLAUDE_SETTINGS, 0o600);
  console.log(result.changed ? 'Removed Agent Bar Claude Code hooks.' : 'No Agent Bar Claude Code hooks found.');
  if (backup) console.log('  backup: ' + backup);
}

function installCodex() {
  fs.mkdirSync(ADAPTERS, { recursive: true, mode: 0o700 });
  fs.chmodSync(ADAPTERS, 0o700);
  const wrapper = path.join(ADAPTERS, 'codex-agentbar');
  const body = `#!/bin/bash
set -u
NODE=${shellQuote(process.execPath)}
REPORT=${shellQuote(REPORT)}
PROJECT="$(basename "$PWD")"
"$NODE" "$REPORT" --id codex-cli --name "Codex CLI" --status running --project "$PROJECT" --tool "Codex" >/dev/null 2>&1
( while sleep 45; do
    "$NODE" "$REPORT" --id codex-cli --status running --project "$PROJECT" >/dev/null 2>&1
  done ) &
HEARTBEAT=$!
ORIGINAL="\${AGENTBAR_CODEX_BIN:-$(command -v codex || true)}"
if [ -z "$ORIGINAL" ] || [ ! -x "$ORIGINAL" ]; then
  echo "agentbar: cannot find the original codex executable" >&2
  kill "$HEARTBEAT" 2>/dev/null
  exit 127
fi
"$ORIGINAL" "$@"
STATUS=$?
kill "$HEARTBEAT" 2>/dev/null
if [ "$STATUS" -eq 0 ]; then
  "$NODE" "$REPORT" --id codex-cli --status done --detail "exit 0" >/dev/null 2>&1
else
  "$NODE" "$REPORT" --id codex-cli --status failed --detail "exit $STATUS" >/dev/null 2>&1
fi
exit "$STATUS"
`;
  fs.writeFileSync(wrapper, body, { mode: 0o755 });
  fs.chmodSync(wrapper, 0o755);
  console.log('Codex adapter wrapper written');
  console.log('  wrapper: ' + wrapper);
  console.log('  add this line to ~/.zshrc, then restart the shell:');
  console.log('    alias codex=' + shellQuote(wrapper));
  console.log('  report:  ' + REPORT);
}

function status() {
  const claude = fs.existsSync(CLAUDE_SETTINGS) ? readJSON(CLAUDE_SETTINGS, {}) : null;
  const hooks = claude && claude.hooks ? claude.hooks : {};
  let installed = 0;
  for (const event of Object.keys(hooks)) {
    const groups = hooks[event];
    if (!Array.isArray(groups)) continue;
    for (const group of groups) {
      if (!group || !Array.isArray(group.hooks)) continue;
      for (const hook of group.hooks) {
        if (hook && typeof hook.command === 'string' && hook.command.includes(MARKER)) installed++;
      }
    }
  }
  console.log('Agent Bar adapters');
  console.log('  report:        ' + REPORT);
  console.log('  Claude Code:   ' + (installed > 0 ? installed + ' hook(s) in ' + CLAUDE_SETTINGS : 'not installed'));
  console.log('  Codex wrapper: ' + (fs.existsSync(path.join(ADAPTERS, 'codex-agentbar')) ? path.join(ADAPTERS, 'codex-agentbar') : 'not installed'));
}

function main() {
  const command = process.argv[2] || 'status';
  if (command === 'claude') return installClaude();
  if (command === 'uninstall-claude') return uninstallClaude();
  if (command === 'codex') return installCodex();
  if (command === 'status') return status();
  console.log('usage: node tools/agentbar-install-adapter.mjs claude|codex|status|uninstall-claude');
  process.exit(2);
}

try {
  main();
} catch (error) {
  console.error('agentbar adapter error: ' + (error && error.message ? error.message : error));
  process.exit(1);
}
