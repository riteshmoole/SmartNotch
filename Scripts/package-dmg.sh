#!/bin/bash
# Packages build/SmartNotch.app into a drag-to-Applications DMG.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -d build/SmartNotch.app ] || ./Scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/SmartNotch.app/Contents/Info.plist)
STAGE="build/dmg-stage"
DMG="build/SmartNotch-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/SmartNotch.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.txt "$STAGE/How to open SmartNotch.txt"
hdiutil create -volname "SmartNotch $VERSION" -srcfolder "$STAGE" -format UDZO -fs APFS "$DMG" -quiet 2>/dev/null \
  || hdiutil create -volname "SmartNotch $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG" -quiet
if security find-certificate -c "SmartNotch Signing" >/dev/null 2>&1; then codesign --force --sign "SmartNotch Signing" "$DMG"; else codesign --force --sign - "$DMG"; fi
rm -rf "$STAGE"
# Unversioned copy: lets https://github.com/<owner>/SmartNotch/releases/latest/download/SmartNotch.dmg
# stay a permanent link across releases.
cp "$DMG" build/SmartNotch.dmg
shasum -a 256 "$DMG"
echo "Packaged $DMG (+ build/SmartNotch.dmg)"
