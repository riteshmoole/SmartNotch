#!/bin/bash
# Builds the vendored ungive/mediaremote-adapter (BSD-3) without cmake.
# Output: build/adapter/MediaRemoteAdapter.framework, build/adapter/MediaRemoteAdapterTestClient
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ThirdParty/mediaremote-adapter"
OUT="$ROOT/build/adapter"
FW="$OUT/MediaRemoteAdapter.framework"
ARCHS="${ARCHS:--arch arm64}"
rm -rf "$FW"; mkdir -p "$FW/Versions/A/Resources" "$FW/Versions/A/Headers"
clang $ARCHS -dynamiclib -fobjc-arc -fvisibility=default -mmacosx-version-min=14.0 \
  -I"$SRC/include" -I"$SRC/src" \
  "$SRC"/src/adapter/*.m "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$FW/Versions/A/MediaRemoteAdapter"
cp "$SRC/include/MediaRemoteAdapter.h" "$FW/Versions/A/Headers/"
cat > "$FW/Versions/A/Resources/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PL
(cd "$FW/Versions" && ln -sfn A Current)
(cd "$FW" && ln -sfn Versions/Current/MediaRemoteAdapter MediaRemoteAdapter && ln -sfn Versions/Current/Resources Resources && ln -sfn Versions/Current/Headers Headers)
clang $ARCHS -fobjc-arc -mmacosx-version-min=14.0 -I"$SRC/src/test" \
  "$SRC/src/test/main.m" "$SRC/src/test/NowPlayingTest.m" \
  -framework Foundation -framework MediaPlayer -o "$OUT/MediaRemoteAdapterTestClient"
cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/"
codesign --force --deep --sign - "$FW" >/dev/null
codesign --force --sign - "$OUT/MediaRemoteAdapterTestClient" >/dev/null
echo "Built adapter -> $OUT"
