#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"
APP="$ROOT_DIR/artifacts/WindowSwitcher.app"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION" --disable-automatic-resolution
BIN_PATH="$(swift build -c "$CONFIGURATION" --disable-automatic-resolution --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/WindowSwitcher" "$APP/Contents/MacOS/WindowSwitcher"
find "$BIN_PATH" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;
cp WindowSwitcher/Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICONSET="$ROOT_DIR/artifacts/AppIcon.iconset"
ICONSRC="$ROOT_DIR/WindowSwitcher/Assets.xcassets/AppIcon.appiconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp "$ICONSRC/icon_16x16.png"     "$ICONSET/icon_16x16.png"
cp "$ICONSRC/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$ICONSRC/icon_32x32.png"     "$ICONSET/icon_32x32.png"
cp "$ICONSRC/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$ICONSRC/icon_128x128.png"   "$ICONSET/icon_128x128.png"
cp "$ICONSRC/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$ICONSRC/icon_256x256.png"   "$ICONSET/icon_256x256.png"
cp "$ICONSRC/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$ICONSRC/icon_512x512.png"   "$ICONSET/icon_512x512.png"
cp "$ICONSRC/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --deep --options runtime \
  --entitlements WindowSwitcher/Resources/WindowSwitcher.entitlements \
  --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

printf '%s\n' "$APP"
