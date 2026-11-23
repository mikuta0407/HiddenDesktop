#!/bin/zsh
# HiddenDesktop.app をビルドする (Apple Silicon / Intel の universal binary)
#   ./build.sh            -> build/HiddenDesktop.app
#   ./build.sh --zip      -> さらに build/HiddenDesktop-v<VERSION>-macos-universal.zip
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.0.0
APP=build/HiddenDesktop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -o "build/obj/HiddenDesktop-$arch" Sources/main.swift
done
lipo -create -output "$APP/Contents/MacOS/HiddenDesktop" build/obj/HiddenDesktop-{arm64,x86_64}

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HiddenDesktop</string>
  <key>CFBundleIdentifier</key><string>net.mikuta0407.HiddenDesktop</string>
  <key>CFBundleExecutable</key><string>HiddenDesktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--zip" ]]; then
  ZIP="build/HiddenDesktop-v$VERSION-macos-universal.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Zipped: $ZIP"
  shasum -a 256 "$ZIP"
fi
