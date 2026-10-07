#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)/AppIcon.iconset"
swift "$ROOT/Scripts/make-icon.swift" "$TMP"
iconutil -c icns "$TMP" -o "$ROOT/Resources/AppIcon.icns"
cp "$TMP/icon_512x512.png" "$ROOT/docs/icon.png"
echo "Wrote Resources/AppIcon.icns"
