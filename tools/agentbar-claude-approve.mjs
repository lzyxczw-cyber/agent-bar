#!/usr/bin/env node
/**
 * agentbar-claude-approve.mjs — Claude Code PermissionRequest hook.
 *
 * Claude Code runs this only when it is about to show a permission dialog.
 * We mirror that prompt into Agent Bar: write a pending request, wait for the
 * App's decision file, then answer allow/deny on the user's behalf.
 *
 * If anything is wrong (App not running, malformed input, timeout) the hook
 * exits 0 without output, which leaves Claude's native dialog in charge.
 * It never blocks a tool call and never allows one on its own.
 *
 * Environment (the installer sets TOOLS; tests set the rest):
 *   AGENTBAR_CLAUDE_APPROVAL_DIR   default ~/Library/Application Support/AgentBar/claude-approvals
 *   AGENTBAR_CLAUDE_APPROVAL_TOOLS default ^Bash$ (regex matched against tool_name)
 *   AGENTBAR_CLAUDE_APPROVAL_WAIT_MS default 40000
 *   AGENTBAR_CLAUDE_APPROVAL_POLL_MS default 150
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  CLAUDE_APPROVAL_WAIT_MS, CLAUDE_APPROVAL_POLL_MS,
  claudeApprovalToolAllowed, claudeApprovalOutput, claudeApprovalDecision,
  claudeHeartbeatFresh, claudeApprovalRequest
} from './lib/claude-approval-logic.mjs';

const MAX_INPUT_BYTES = 1024 * 1024;

function approvalDir () {
  return process.env.AGENTBAR_CLAUDE_APPROVAL_DIR ||
    path.join (os.homedir (), 'Library', 'Application Support', 'AgentBar', 'claude-approvals');
}

function numberEnv (name, fallback) {
  const value = Number (process.env[name]);
  return Number.isFinite (value) && value >= 0 ? value : fallback;
}

function heartbeatFresh (dir) {
  try {
    return claudeHeartbeatFresh (fs.statSync (path.join (dir, 'heartbeat')).mtimeMs, Date.now ());
  } catch {
    return false;
  }
}

function writeAtomic (file, payload) {
  const temporary = file + '.tmp';
  fs.writeFileSync (temporary, JSON.stringify (payload), { mode: 0o600 });
  fs.chmodSync (temporary, 0o600);
  fs.renameSync (temporary, file);
}

function readJSON (file) {
  try { return JSON.parse (fs.readFileSync (file, 'utf8')); } catch { return null; }
}

function sleep (ms) {
  return new Promise ((resolve) => setTimeout (resolve, ms));
}

async function main () {
  const raw = fs.readFileSync (0, 'utf8');
  if (!raw || raw.length > MAX_INPUT_BYTES) return null;
  let input;
  try { input = JSON.parse (raw); } catch { return null; }

  if (!claudeApprovalToolAllowed (input && input.tool_name, process.env.AGENTBAR_CLAUDE_APPROVAL_TOOLS || '^Bash$')) return null;

  const dir = approvalDir ();
  if (!heartbeatFresh (dir)) return null;

  const pendingDir = path.join (dir, 'pending');
  const decisionDir = path.join (dir, 'decisions');
  fs.mkdirSync (pendingDir, { recursive: true, mode: 0o700 });
  fs.mkdirSync (decisionDir, { recursive: true, mode: 0o700 });
  fs.chmodSync (pendingDir, 0o700);
  fs.chmodSync (decisionDir, 0o700);

  const id = crypto.randomUUID ();
  const nonce = crypto.randomBytes (16).toString ('hex');
  const request = claudeApprovalRequest (input, { now: Date.now (), id, nonce });
  if (!request) return null;

  const pendingFile = path.join (pendingDir, id + '.json');
  const decisionFile = path.join (decisionDir, id + '.json');
  writeAtomic (pendingFile, request);

  try {
    const deadline = Date.now () + numberEnv ('AGENTBAR_CLAUDE_APPROVAL_WAIT_MS', CLAUDE_APPROVAL_WAIT_MS);
    const poll = numberEnv ('AGENTBAR_CLAUDE_APPROVAL_POLL_MS', CLAUDE_APPROVAL_POLL_MS);
    while (Date.now () < deadline) {
      if (!heartbeatFresh (dir)) return null;
      const payload = readJSON (decisionFile);
      if (payload) {
        const decision = claudeApprovalDecision (payload, { id, nonce });
        if (decision) {
          return decision === 'allow'
            ? claudeApprovalOutput ('allow', 'Agent Bar 面板已允许')
            : claudeApprovalOutput ('deny', 'Agent Bar 面板已拒绝');
        }
      }
      await sleep (Math.max (20, poll));
    }
    return null;
  } finally {
    try { fs.unlinkSync (pendingFile); } catch {}
    try { fs.unlinkSync (decisionFile); } catch {}
  }
}

main ().then ((output) => {
  if (output) process.stdout.write (JSON.stringify (output));
  process.exit (0);
}).catch (() => {
  process.exit (0);
});
