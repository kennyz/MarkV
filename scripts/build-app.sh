#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Markv.app"
ICONSET="$BUILD_DIR/Markv.iconset"
SIGN_IDENTITY="${MARKV_SIGN_IDENTITY:--}"

export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"

swift build \
  --configuration release \
  --disable-sandbox \
  --scratch-path "$BUILD_DIR"

BIN_DIR="$(swift build --configuration release --disable-sandbox --scratch-path "$BUILD_DIR" --show-bin-path)"

rm -rf "$APP_BUNDLE" "$ICONSET"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$ICONSET"

cp "$BIN_DIR/Markv" "$APP_BUNDLE/Contents/MacOS/Markv"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  pixels="${spec%% *}"
  name="${spec#* }"
  swift "$PROJECT_DIR/scripts/make-icon.swift" "$pixels" "$ICONSET/$name"
done

swift "$PROJECT_DIR/scripts/make-icns.swift" "$ICONSET" "$APP_BUNDLE/Contents/Resources/Markv.icns"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_BUNDLE"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"
fi

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "Built $APP_BUNDLE"
