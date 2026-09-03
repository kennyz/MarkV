#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/Resources/Markv.entitlements"
APP_BUNDLE="$PROJECT_DIR/dist/Markv.app"
RELEASE_DIR="$PROJECT_DIR/release"

: "${MARKV_APP_STORE_SIGN_IDENTITY:?Set MARKV_APP_STORE_SIGN_IDENTITY to your Mac App Distribution certificate name}"
: "${MARKV_INSTALLER_SIGN_IDENTITY:?Set MARKV_INSTALLER_SIGN_IDENTITY to your Mac Installer Distribution certificate name}"
: "${MARKV_PROVISIONING_PROFILE:?Set MARKV_PROVISIONING_PROFILE to the App Store distribution .provisionprofile path}"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full Xcode installation must be selected with xcode-select before building for App Store Connect." >&2
  exit 1
fi

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_MAJOR="${SDK_VERSION%%.*}"
if (( SDK_MAJOR < 26 )); then
  echo "App Store Connect requires Xcode 26 / macOS 26 SDK or later; active SDK is $SDK_VERSION." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PKG_PATH="$RELEASE_DIR/MarkV-${VERSION}-${BUILD}-Mac-App-Store.pkg"

MARKV_SIGN_IDENTITY="$MARKV_APP_STORE_SIGN_IDENTITY" \
MARKV_SIGN_STYLE="app-store" \
MARKV_ENTITLEMENTS="$ENTITLEMENTS" \
MARKV_PROVISIONING_PROFILE="$MARKV_PROVISIONING_PROFILE" \
  "$SCRIPT_DIR/build-app.sh"

if xattr -r "$APP_BUNDLE" | grep -q '^com\.apple\.quarantine$'; then
  echo "The app bundle still contains a quarantine attribute." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" 2>"$PROJECT_DIR/.build/mas-entitlements.plist"
plutil -lint "$PROJECT_DIR/.build/mas-entitlements.plist"

mkdir -p "$RELEASE_DIR"
rm -f "$PKG_PATH"
productbuild \
  --component "$APP_BUNDLE" /Applications \
  --sign "$MARKV_INSTALLER_SIGN_IDENTITY" \
  --timestamp \
  "$PKG_PATH"

pkgutil --check-signature "$PKG_PATH"
shasum -a 256 "$PKG_PATH"
echo "Built Mac App Store upload package: $PKG_PATH"
echo "Validate with: xcrun altool --validate-app -f '$PKG_PATH' -t macos -u APPLE_ID -p APP_SPECIFIC_PASSWORD"
