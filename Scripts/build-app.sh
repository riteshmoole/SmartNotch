#!/bin/bash
# Builds SmartNotch.app with SwiftPM (no Xcode needed) and ad-hoc signs it.
# Usage: ./Scripts/build-app.sh [release|debug]
set -euo pipefail
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -d build/adapter/MediaRemoteAdapter.framework ] || ./Scripts/build-adapter.sh
[ -f Resources/AppIcon.icns ] || ./Scripts/make-icon.sh

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/SmartNotch"

APP="build/SmartNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN" "$APP/Contents/MacOS/SmartNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Themes "$APP/Contents/Resources/Themes"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp build/adapter/mediaremote-adapter.pl "$APP/Contents/Resources/"
cp -R build/adapter/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/"
cp build/adapter/MediaRemoteAdapterTestClient "$APP/Contents/Helpers/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/" 2>/dev/null || true

# Signing identity: "SmartNotch Signing" (self-signed, from Scripts/create-signing-cert.sh) when
# present, so macOS permission grants survive rebuilds/updates; otherwise ad-hoc ("-"), which is
# valid but changes every build. Override with SIGN_IDENTITY=... . Neither is notarized.
# Hardened runtime (--options runtime) is on so the same bundle can be notarized later.
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-certificate -c "SmartNotch Signing" >/dev/null 2>&1; then SIGN_IDENTITY="SmartNotch Signing"; else SIGN_IDENTITY="-"; fi
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --entitlements Resources/SmartNotch.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($CONFIG, signed with: $SIGN_IDENTITY)"
