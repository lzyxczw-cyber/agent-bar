#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Runtime files live outside ~/Documents so macOS never asks for Documents access.
# The packaged app performs this same program sync from Contents/Resources/bridge.
# Dev restart drops the previous snapshot below; control/, audit.log, and
# usage-state.json stay so a restarted bridge keeps its token and usage baseline.
APP_SUPPORT="$HOME/Library/Application Support/AgentBar"
BRIDGE_DEST="$APP_SUPPORT/bridge"
./tools/sync-bundled-bridge.sh "$PWD/bridge" "$BRIDGE_DEST"
rm -f "$BRIDGE_DEST/status.json"

pkill -f 'Agent Bar.app/Contents/MacOS/AgentBar' 2>/dev/null || pkill -f 'AgentBar.app/Contents/MacOS/AgentBar' 2>/dev/null || true
pkill -f 'Application Support/AgentBar/bridge/dsh-bridge.mjs' 2>/dev/null || true
pkill -f 'agentbar/bridge/dsh-bridge.mjs' 2>/dev/null || true
# Clear adapters left by an older run so the app's bundled copy can take over.
pkill -f 'agentbar-app-adapters.mjs' 2>/dev/null || true
sleep 0.5

open "Agent Bar.app" --args --quiet
sleep 1

if pgrep -f 'Agent Bar.app/Contents/MacOS/AgentBar' >/dev/null; then
  # The packaged app autostarts its bundled desktop adapters (single-instance
  # lock). Launching a second copy from the checkout here raced the app's copy
  # and could leave no adapter running after a relaunch.
  echo "Agent Bar started."
  echo "  - bar:      top of the screen (covers the system menu bar while running)"
  echo "  - panel:    click the bar; click an avatar to switch agent"
  echo "  - menu bar: push the cursor to the very top edge to reveal it"
  echo "  - quit:     control-option-command-Q  (or right-click the bar)"
  echo "  - datasrc:  $BRIDGE_DEST/status.json (bridge auto-starts)"
  echo "  - adapters: Codex / WorkBuddy / Grok Bot (autostarted by the app)"
else
  echo "failed to start Agent Bar.app" >&2
  exit 1
fi
