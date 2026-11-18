#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> compiling agentbar"
# Pin the deployment target: without this, swiftc inherits the SDK/host default
# (minos 28.0 on this machine) and LaunchServices refuses to launch the app on
# any OS older than that with error -10825.
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 \
  main.swift Support.swift Models.swift Views.swift Chrome.swift AppDelegate.swift ReleaseUpdate.swift \
  -o agentbar

APP="Agent Bar.app"
echo "==> packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/tools" "$APP/Contents/Resources/bridge"
cp agentbar "$APP/Contents/MacOS/AgentBar"
cp tools/agentbar-app-adapters.mjs "$APP/Contents/Resources/tools/agentbar-app-adapters.mjs"
# The watcher imports ./lib/adapter-logic.mjs. A DMG install has no repo
# beside the app; without this file it exits immediately (ERR_MODULE_NOT_FOUND)
# and Codex / WorkBuddy / Grok Bot / Hermes never appear. DSH does not use it.
mkdir -p "$APP/Contents/Resources/tools/lib"
cp -R tools/lib/. "$APP/Contents/Resources/tools/lib/"
if [ ! -f "$APP/Contents/Resources/tools/lib/adapter-logic.mjs" ]; then
  echo "error: $APP is missing Contents/Resources/tools/lib/adapter-logic.mjs" >&2
  exit 1
fi

# The released app has no repo checkout beside it. Ship the DSH bridge
# program inside the bundle; the app copies it to Application Support
# on launch. Generated runtime files are not part of this copy.
echo "==> bundling DSH bridge"
cp tools/sync-bundled-bridge.sh "$APP/Contents/Resources/tools/sync-bundled-bridge.sh"
chmod +x "$APP/Contents/Resources/tools/sync-bundled-bridge.sh"
./tools/sync-bundled-bridge.sh bridge "$APP/Contents/Resources/bridge"

# Confirmed 128×128 agent icons, copied unchanged. The app scales them at
# draw time; PixelSprite is only the fallback when a PNG set is missing.
if [ -d Resources/agents ]; then
  echo "==> bundling agent icons"
  rm -rf "$APP/Contents/Resources/agents"
  cp -R Resources/agents "$APP/Contents/Resources/agents"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>AgentBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.lzy.agentbar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Agent Bar</string>
    <key>CFBundleDisplayName</key>
    <string>Agent Bar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.9</string>
    <key>CFBundleVersion</key>
    <string>0.3.9</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 lzyxczw-cyber. MIT License.</string>
</dict>
</plist>
PLIST

if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi

# Strip extended attributes first: a FinderInfo/resource-fork xattr makes
# codesign fail with "resource fork, Finder information, or similar detritus
# not allowed", which silently leaves the bundle with no resource seal.
xattr -cr "$APP" 2>/dev/null || true
if ! codesign --force --sign - --identifier com.lzy.agentbar "$APP"; then
  echo "warning: ad-hoc codesign failed; notifications and LaunchServices may refuse this build" >&2
fi
codesign --verify --strict "$APP" || echo "warning: signature verification failed" >&2

echo "built: $(pwd)/agentbar"
echo "app:   $(pwd)/$APP"
