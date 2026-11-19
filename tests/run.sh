#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/agentbar-tests"
echo "==> running pure-function tests"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  Support.swift tests/main.swift -o "$OUT"
"$OUT"

if command -v node >/dev/null 2>&1; then
  echo "==> running bridge logic tests"
  node --test tests/bridge-logic.test.mjs tests/adapter-logic.test.mjs tests/adapter-install.test.mjs tests/sync-bundled-bridge.test.mjs tests/bridge-runtime.test.mjs tests/claude-adapter.test.mjs tests/claude-approval.test.mjs
else
  echo "node not found; bridge logic tests are required" >&2
  exit 1
fi
