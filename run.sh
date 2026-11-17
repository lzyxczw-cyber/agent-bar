#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x ./agentbar ]; then
  ./build.sh
fi
exec ./agentbar "$@"
