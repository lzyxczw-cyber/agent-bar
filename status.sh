#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_SUPPORT="$HOME/Library/Application Support/AgentBar"
FEED="$APP_SUPPORT/bridge/status.json"
[ -f "$FEED" ] || FEED="bridge/status.json"

echo "== app =="
if pgrep -fl 'Agent Bar.app/Contents/MacOS/AgentBar'; then :; else echo "not running"; fi

echo "== bridge =="
if pgrep -fl 'AgentBar/bridge/dsh-bridge.mjs|agentbar/bridge/dsh-bridge.mjs'; then :; else echo "not running"; fi

echo "== adapters =="
if pgrep -fl 'tools/agentbar-app-adapters.mjs'; then :; else echo "not running"; fi

echo "== feed =="
if [ -f "$FEED" ]; then
  stat -f 'status.json modified: %Sm (%N)' -t '%Y-%m-%d %H:%M:%S' "$FEED"
  /usr/bin/python3 - "$FEED" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
c = d.get("counts") or {}
print("connected:", (d.get("dsh") or {}).get("connected"),
      "| agents:", c.get("agents"), "| running:", c.get("running"), "| approvals:", c.get("approvals"))
u = d.get("usage") or {}
acc = d.get("account") or {}
print("usage tokensToday:", u.get("tokensToday"), "| account:", acc.get("status"), acc.get("currency"), acc.get("balance"))
PY
else
  echo "no status.json yet"
fi

echo "== recent app log =="
tail -5 /tmp/agentbar.log 2>/dev/null || echo "no log"
