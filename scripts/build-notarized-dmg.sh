#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
APP_BUNDLE="$PROJECT_DIR/dist/Markv.app"
RELEASE_DIR="$PROJECT_DIR/release"

: "${MARKV_SIGN_IDENTITY:?Set MARKV_SIGN_IDENTITY to your Developer ID Application certificate name}"
NOTARY_PROFILE="${MARKV_NOTARY_PROFILE:-markv-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ARCHITECTURE="$(uname -m)"
DMG_PATH="$RELEASE_DIR/MarkV-${VERSION}-macOS-${ARCHITECTURE}.dmg"
STAGING_DIR="$(mktemp -d /private/tmp/markv-notarize.XXXXXX)"

cleanup() {
  if [[ "$STAGING_DIR" == /private/tmp/markv-notarize.* ]]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

MARKV_SIGN_IDENTITY="$MARKV_SIGN_IDENTITY" "$SCRIPT_DIR/build-app.sh"

mkdir -p "$RELEASE_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/Markv.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "MarkV" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign \
  --force \
  --timestamp \
  --sign "$MARKV_SIGN_IDENTITY" \
  "$DMG_PATH"

codesign --verify --verbose=2 "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH"
echo "Built, signed, notarized, and stapled $DMG_PATH"
