#!/usr/bin/env bash
# Package Agent Bar.app into a DMG, re-signing outside ~/Documents so the
# File Provider detritus bug cannot invalidate the signature.
#
#   ./package.sh                         # ad-hoc signed DMG (local testing)
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./package.sh
#
# Notarization still needs an Apple Developer team + credentials; see the
# printed instructions after the DMG is produced.
set -euo pipefail
cd "$(dirname "$0")"

APP="Agent Bar.app"
STAMP="$(date +%Y%m%d-%H%M%S)"
STAGE="${TMPDIR:-/tmp}/agentbar-package-${STAMP}"
IDENTITY="${CODESIGN_IDENTITY:--}"
KEYCHAIN="${CODESIGN_KEYCHAIN:-}"
KEYCHAIN_ARGS=()
if [ -n "$KEYCHAIN" ]; then
  KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
fi

echo "==> building"
./build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="Agent-Bar-${VERSION}.dmg"

echo "==> staging in $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto --norsrc "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
xattr -cr "$STAGE/$APP"

echo "==> signing ($IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - --identifier com.lzy.agentbar "$STAGE/$APP"
else
  codesign --force --deep --options runtime --timestamp "${KEYCHAIN_ARGS[@]}" --sign "$IDENTITY" --identifier com.lzy.agentbar "$STAGE/$APP"
fi
codesign --verify --strict --verbose=2 "$STAGE/$APP"
SPCTL="$(spctl -a -vv "$STAGE/$APP" 2>&1 || true)"
echo "    $SPCTL"

echo "==> creating $DMG"
rm -f "$DMG"
hdiutil create -volname "Agent Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [ "$IDENTITY" != "-" ]; then
  codesign --force "${KEYCHAIN_ARGS[@]}" --sign "$IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi
rm -rf "$STAGE"

if [ "${NOTARIZE:-0}" = "1" ]; then
  if [ "$IDENTITY" = "-" ]; then
    echo "NOTARIZE=1 requires CODESIGN_IDENTITY (Developer ID Application)" >&2
    exit 2
  fi
  echo "==> notarizing $DMG"
  if [ -n "${NOTARY_KEY:-}" ]; then
    : "${NOTARY_KEY_ID:?set NOTARY_KEY_ID with NOTARY_KEY}"
    NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID")
    if [ -n "${NOTARY_ISSUER:-}" ]; then
      NOTARY_ARGS+=(--issuer "$NOTARY_ISSUER")
    fi
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
  elif [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    : "${NOTARY_APPLE_ID:?set NOTARY_APPLE_ID (or NOTARY_KEY/NOTARY_PROFILE)}"
    : "${NOTARY_TEAM_ID:?set NOTARY_TEAM_ID}"
    : "${NOTARY_PASSWORD:?set NOTARY_PASSWORD (app-specific password)}"
    xcrun notarytool submit "$DMG" \
      --apple-id "$NOTARY_APPLE_ID" \
      --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_PASSWORD" --wait
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

# Hash after code signing/notarization/staple: stapling modifies the DMG.
shasum -a 256 "$DMG" | tee "$DMG.sha256"

if [ "$IDENTITY" = "-" ]; then
  echo
  echo "Ad-hoc DMG written: $DMG"
  echo "For distribution, set CODESIGN_IDENTITY and notarize:"
else
  echo
  echo "Signed DMG written: $DMG"
  echo "Notarize with:"
fi
echo "  NOTARIZE=1 CODESIGN_IDENTITY=... NOTARY_KEY=... NOTARY_KEY_ID=... NOTARY_ISSUER=... ./package.sh"
echo "  (or NOTARY_PROFILE=... / Apple ID + app-specific password; see docs/SIGNING.md)"
