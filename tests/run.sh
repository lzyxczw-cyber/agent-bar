#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/agentbar-tests"
echo "==> running pure-function tests"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  Support.swift tests/main.swift -o "$OUT"
"$OUT"
