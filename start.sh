#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Runtime files live outside ~/Documents so macOS never asks for Documents access.
APP_SUPPORT="$HOME/Library/Application Support/AgentBar"
BRIDGE_DEST="$APP_SUPPORT/bridge"
mkdir -p "$BRIDGE_DEST"
rm -rf "$BRIDGE_DEST/lib" "$BRIDGE_DEST/vendor"
cp -R bridge/lib bridge/vendor bridge/dsh-bridge.mjs "$BRIDGE_DEST/"
cp bridge/README.md "$BRIDGE_DEST/" 2>/dev/null || true
rm -f "$BRIDGE_DEST/status.json"

pkill -f 'Agent Bar.app/Contents/MacOS/AgentBar' 2>/dev/null || pkill -f 'AgentBar.app/Contents/MacOS/AgentBar' 2>/dev/null || true
pkill -f 'Application Support/AgentBar/bridge/dsh-bridge.mjs' 2>/dev/null || true
pkill -f 'agentbar/bridge/dsh-bridge.mjs' 2>/dev/null || true
sleep 0.5

open "Agent Bar.app" --args --quiet
sleep 1

if pgrep -f 'Agent Bar.app/Contents/MacOS/AgentBar' >/dev/null; then
  # Local desktop-app adapters (Codex / WorkBuddy / Grok Bot). They read only
  # the apps' local state files and write the generic agent reports.
  if [ -f tools/agentbar-app-adapters.mjs ]; then
    pkill -f 'tools/agentbar-app-adapters.mjs' 2>/dev/null || true
    NODE_BIN="$(command -v node || true)"
    [ -n "$NODE_BIN" ] || NODE_BIN=/usr/local/bin/node
    nohup "$NODE_BIN" tools/agentbar-app-adapters.mjs >>/tmp/agentbar-adapters.log 2>&1 &
  fi
  echo "Agent Bar started."
  echo "  - bar:      top of the screen (covers the system menu bar while running)"
  echo "  - panel:    click the bar; click an avatar to switch agent"
  echo "  - menu bar: push the cursor to the very top edge to reveal it"
  echo "  - quit:     control-option-command-Q  (or right-click the bar)"
  echo "  - datasrc:  $BRIDGE_DEST/status.json (bridge auto-starts)"
  echo "  - adapters: Codex / WorkBuddy / Grok Bot (tools/agentbar-app-adapters.mjs)"
else
  echo "failed to start Agent Bar.app" >&2
  exit 1
fi
