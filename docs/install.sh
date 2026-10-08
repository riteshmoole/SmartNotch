#!/bin/bash
# Installs (or updates) SmartNotch from the latest GitHub release.
#   curl -fsSL https://riteshmoole.github.io/SmartNotch/install.sh | bash
# Files downloaded with curl aren't flagged as "from the internet", so macOS doesn't ask you to
# approve the app in Privacy & Security. In exchange, this script checks the download is signed by
# SmartNotch's own certificate before installing it. Read it first if you like: it's short.
set -euo pipefail

URL="https://github.com/riteshmoole/SmartNotch/releases/latest/download/SmartNotch.zip"
REQUIREMENT='identifier "com.rick.SmartNotch" and certificate leaf = H"c1bf14c91b7a237903b652cd8ce8b664d9fc106e"'
DEST="${SMARTNOTCH_DEST:-/Applications}"

fail() { echo "SmartNotch: $*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "this installer is for macOS."
[ "$(uname -m)" = arm64 ] || fail "SmartNotch needs a Mac with Apple Silicon (M1 or newer)."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 14 ] || fail "SmartNotch needs macOS 14 Sonoma or later."

if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading SmartNotch…"
curl -fL --progress-bar -o "$TMP/SmartNotch.zip" "$URL"
ditto -x -k "$TMP/SmartNotch.zip" "$TMP"
[ -d "$TMP/SmartNotch.app" ] || fail "the download didn't contain SmartNotch.app."

codesign --verify --deep --strict "$TMP/SmartNotch.app" 2>/dev/null \
  || fail "the download's signature is broken. Nothing was installed."
codesign --verify -R="$REQUIREMENT" "$TMP/SmartNotch.app" 2>/dev/null \
  || fail "the download isn't signed by SmartNotch's certificate. Nothing was installed."

if pgrep -x SmartNotch >/dev/null; then
  echo "Quitting the running SmartNotch…"
  pkill -x SmartNotch || true
  for _ in $(seq 1 50); do pgrep -x SmartNotch >/dev/null || break; sleep 0.1; done
fi

rm -rf "$DEST/SmartNotch.app"
ditto "$TMP/SmartNotch.app" "$DEST/SmartNotch.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$DEST/SmartNotch.app/Contents/Info.plist")
echo "Installed SmartNotch $VERSION in $DEST. Opening it…"
open "$DEST/SmartNotch.app"
