#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/Ring Stats.app"
VERSION="${MARKETING_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/native/Info.plist")}"
DMG_PATH="$OUTPUT_DIR/Ring-Stats-$VERSION.dmg"

: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${APPLE_NOTARY_PROFILE:?Set APPLE_NOTARY_PROFILE to a notarytool Keychain profile}"

if [[ "$APPLE_SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "APPLE_SIGNING_IDENTITY must be a Developer ID Application identity." >&2
  exit 1
fi

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F "$APPLE_SIGNING_IDENTITY" >/dev/null; then
  echo "Signing identity was not found in the current Keychain: $APPLE_SIGNING_IDENTITY" >&2
  exit 1
fi

CODESIGN_IDENTITY="$APPLE_SIGNING_IDENTITY" \
DMG_CODESIGN_IDENTITY="$APPLE_SIGNING_IDENTITY" \
"$PROJECT_DIR/scripts/create_dmg.sh"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

xcrun notarytool submit \
  "$DMG_PATH" \
  --keychain-profile "$APPLE_NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
/usr/sbin/spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  "$DMG_PATH"

echo "Signed, notarized, and stapled: $DMG_PATH"
/usr/bin/shasum -a 256 "$DMG_PATH"
