#!/bin/bash
# Packages build/SmartNotch.app into a ZIP, the main download.
# A ZIP is used instead of a DMG because macOS blocks an unnotarized DMG before it even opens;
# unzipping shows no warning, so users only approve the app itself once.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -d build/SmartNotch.app ] || ./Scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/SmartNotch.app/Contents/Info.plist)
ZIP="build/SmartNotch-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the code signature and extended attributes intact (plain `zip` can break the signature).
ditto -c -k --sequesterRsrc --keepParent build/SmartNotch.app "$ZIP"
# Unversioned copy: lets https://github.com/<owner>/SmartNotch/releases/latest/download/SmartNotch.zip
# stay a permanent link across releases.
cp "$ZIP" build/SmartNotch.zip
shasum -a 256 "$ZIP"
echo "Packaged $ZIP (+ build/SmartNotch.zip)"
