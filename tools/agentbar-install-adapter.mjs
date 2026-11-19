#!/usr/bin/env node
/**
 * agentbar-install-adapter.mjs — one-shot local adapters for Agent Bar.
 *
 *   node tools/agentbar-install-adapter.mjs claude [--tools <regex>] [--no-approvals]
 *   node tools/agentbar-install-adapter.mjs codex
 *   node tools/agentbar-install-adapter.mjs status
 *   node tools/agentbar-install-adapter.mjs uninstall-claude
 *
 * Claude Code: sessions are read from local transcripts; `claude` also installs
 *   the PermissionRequest approval hook (default matcher ^Bash$).
 *   uninstall-claude removes both the approval hook and hooks from older versions.
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
const HOOKS = path.join(APP_SUPPORT, 'hooks');
const APPROVAL_HOOK = path.join(TOOLS, 'agentbar-claude-approve.mjs');
const APPROVAL_LIB = path.join(TOOLS, 'lib', 'claude-approval-logic.mjs');
const LEGACY_MARKER = 'agentbar-report.mjs';
const APPROVAL_MARKER = 'agentbar-claude-approve.mjs';

function claudeConfigDir() {
  return process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
}

function claudeSettingsFile() {
  return path.join(claudeConfigDir(), 'settings.json');
}

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

function removeHooksByMarker(node, markers = [LEGACY_MARKER, APPROVAL_MARKER]) {
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
        return !markers.some((marker) => command.includes(marker));
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

function installApprovalScripts() {
  fs.mkdirSync(path.join(HOOKS, 'lib'), { recursive: true, mode: 0o700 });
  fs.chmodSync(HOOKS, 0o700);
  const script = path.join(HOOKS, 'agentbar-claude-approve.mjs');
  const lib = path.join(HOOKS, 'lib', 'claude-approval-logic.mjs');
  fs.copyFileSync(APPROVAL_HOOK, script);
  fs.copyFileSync(APPROVAL_LIB, lib);
  fs.chmodSync(script, 0o700);
  fs.chmodSync(lib, 0o600);
  return script;
}

function removeApprovalScripts() {
  try { fs.rmSync(HOOKS, { recursive: true, force: true }); } catch {}
}

function removeStaleLegacyReport() {
  const file = path.join(APP_SUPPORT, 'agents', 'claude-code.json');
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (data && data.id === 'claude-code') {
      fs.unlinkSync(file);
      return true;
    }
  } catch {}
  return false;
}

function installClaude({ tools = '^Bash$', approvals = true } = {}) {
  const projects = path.join(claudeConfigDir(), 'projects');
  console.log('Claude Code sessions are read directly from local transcripts under ' + projects + '; no report hooks are needed.');
  if (!approvals) {
    console.log('Approval hook skipped (--no-approvals). Run without the flag to mirror Bash prompts in Agent Bar.');
    return;
  }

  const settings = claudeSettingsFile();
  if (!fs.existsSync(settings)) {
    const dir = path.dirname(settings);
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    fs.writeFileSync(settings, '{}\n', { mode: 0o600 });
  }
  const node = readJSON(settings, null);
  if (!node || typeof node !== 'object') throw new Error('cannot parse ' + settings);

  const backup = backupFile(settings);
  removeHooksByMarker(node, [LEGACY_MARKER, APPROVAL_MARKER]);
  const hooks = node.hooks && typeof node.hooks === 'object' ? node.hooks : {};
  hooks.PermissionRequest = Array.isArray(hooks.PermissionRequest) ? hooks.PermissionRequest : [];
  const script = installApprovalScripts();
  const command = 'AGENTBAR_CLAUDE_APPROVAL_TOOLS=' + shellQuote(tools) + ' ' +
    shellQuote(process.execPath) + ' ' + shellQuote(script);
  hooks.PermissionRequest.push({
    matcher: tools,
    hooks: [{ type: 'command', timeout: 45, command }]
  });
  node.hooks = hooks;

  fs.writeFileSync(settings, JSON.stringify(node, null, 2) + '\n', { mode: 0o600 });
  fs.chmodSync(settings, 0o600);
  const stale = removeStaleLegacyReport();
  console.log('Installed the Claude Code approval hook (matcher ' + tools + ').');
  console.log('  hook:    ' + script);
  console.log('  timeout: 45s; Agent Bar must be running, otherwise Claude keeps its own prompt.');
  if (stale) console.log('  removed a stale agents/claude-code.json report left by the old hook.');
  if (backup) console.log('  backup:  ' + backup);
}

function uninstallClaude() {
  const settings = claudeSettingsFile();
  if (!fs.existsSync(settings)) {
    console.log('No ' + settings + ' found; nothing to remove.');
    removeApprovalScripts();
    return;
  }
  const node = readJSON(settings, null);
  if (!node || typeof node !== 'object') throw new Error('cannot parse ' + settings);
  const backup = backupFile(settings);
  const result = removeHooksByMarker(node);
  fs.writeFileSync(settings, JSON.stringify(result.node, null, 2) + '\n', { mode: 0o600 });
  fs.chmodSync(settings, 0o600);
  removeApprovalScripts();
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

function countHooks(node, markers) {
  const hooks = node && node.hooks ? node.hooks : {};
  let count = 0;
  let matcher = null;
  for (const event of Object.keys(hooks)) {
    const groups = hooks[event];
    if (!Array.isArray(groups)) continue;
    for (const group of groups) {
      if (!group || !Array.isArray(group.hooks)) continue;
      for (const hook of group.hooks) {
        const command = hook && typeof hook.command === 'string' ? hook.command : '';
        if (markers.some((marker) => command.includes(marker))) {
          count++;
          if (!matcher && typeof group.matcher === 'string') matcher = group.matcher;
        }
      }
    }
  }
  return { count, matcher };
}

function status() {
  const settings = claudeSettingsFile();
  const node = fs.existsSync(settings) ? readJSON(settings, {}) : null;
  const legacy = countHooks(node, [LEGACY_MARKER]);
  const approval = countHooks(node, [APPROVAL_MARKER]);
  const matcher = approval.matcher || '^Bash$';
  const script = path.join(HOOKS, 'agentbar-claude-approve.mjs');
  const lib = path.join(HOOKS, 'lib', 'claude-approval-logic.mjs');
  const scriptsReady = fs.existsSync(script) && fs.existsSync(lib);

  console.log('Agent Bar adapters');
  console.log('  report:        ' + REPORT);
  console.log('  Claude Code:   transcript mode + approval hook (' + matcher + ')' +
    (approval.count > 0 ? '' : ' — not installed'));
  if (!approval.count || !scriptsReady) {
    console.log('                 run: node tools/agentbar-install-adapter.mjs claude');
  }
  if (legacy.count > 0) {
    console.log('                 ' + legacy.count + ' legacy hook(s) in ' + settings + ' — run uninstall-claude');
  }
  console.log('  Codex wrapper: ' + (fs.existsSync(path.join(ADAPTERS, 'codex-agentbar')) ? path.join(ADAPTERS, 'codex-agentbar') : 'not installed'));
}

function main() {
  const args = process.argv.slice(2);
  const command = args[0] && !args[0].startsWith('--') ? args[0] : 'status';
  const toolsIndex = args.indexOf('--tools');
  const tools = toolsIndex >= 0 && args[toolsIndex + 1] ? args[toolsIndex + 1] : '^Bash$';
  const approvals = !args.includes('--no-approvals');
  if (command === 'claude') return installClaude({ tools, approvals });
  if (command === 'uninstall-claude') return uninstallClaude();
  if (command === 'codex') return installCodex();
  if (command === 'status') return status();
  console.log('usage: node tools/agentbar-install-adapter.mjs claude [--tools <regex>] [--no-approvals] | codex | status | uninstall-claude');
  process.exit(2);
}

try {
  main();
} catch (error) {
  console.error('agentbar adapter error: ' + (error && error.message ? error.message : error));
  process.exit(1);
}
