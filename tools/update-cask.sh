#!/usr/bin/env bash
# Update Casks/agent-bar.rb version + sha256 from a built DMG.
#   ./tools/update-cask.sh Agent-Bar-0.3.0.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
DMG="${1:?usage: tools/update-cask.sh <dmg>}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "Agent Bar.app/Contents/Info.plist")"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
python3 - "$VERSION" "$SHA" <<'PY'
import re, sys
from pathlib import Path
version, sha = sys.argv[1], sys.argv[2]
path = Path("Casks/agent-bar.rb")
text = path.read_text()
text = re.sub(r'^  version ".*"$', f'  version "{version}"', text, count=1, flags=re.M)
text = re.sub(r'^  sha256 ".*"$', f'  sha256 "{sha}"', text, count=1, flags=re.M)
path.write_text(text)
print(f"updated Casks/agent-bar.rb -> version {version}, sha256 {sha}")
PY
