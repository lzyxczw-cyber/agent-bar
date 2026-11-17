#!/usr/bin/env bash
set -euo pipefail
pkill -f 'Agent Bar.app/Contents/MacOS/AgentBar' 2>/dev/null || pkill -f 'AgentBar.app/Contents/MacOS/AgentBar' 2>/dev/null || true
pkill -f 'tools/agentbar-app-adapters.mjs' 2>/dev/null || true
pkill -f 'Application Support/AgentBar/bridge/dsh-bridge.mjs' 2>/dev/null || true
pkill -f 'agentbar/bridge/dsh-bridge.mjs' 2>/dev/null || true
sleep 0.4
echo "Agent Bar stopped."
