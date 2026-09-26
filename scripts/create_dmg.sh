#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_NAME="Ring Stats"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
VERSION="${MARKETING_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/native/Info.plist")}"
DMG_PATH="$OUTPUT_DIR/Ring-Stats-$VERSION.dmg"
SKIP_BUILD="${SKIP_BUILD:-0}"
DMG_CODESIGN_IDENTITY="${DMG_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:--}}"

if [[ "$SKIP_BUILD" != "1" ]]; then
  INSTALL_APP=0 "$PROJECT_DIR/scripts/build_app.sh"
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing application bundle: $APP_DIR" >&2
  exit 1
fi

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-dmg.XXXXXX")"
cleanup() { rm -rf "$staging_dir"; }
trap cleanup EXIT

/usr/bin/ditto "$APP_DIR" "$staging_dir/$APP_NAME.app"
/bin/ln -s /Applications "$staging_dir/Applications"
rm -f "$DMG_PATH"

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

if [[ "$DMG_CODESIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign \
    --force \
    --timestamp \
    --sign "$DMG_CODESIGN_IDENTITY" \
    "$DMG_PATH"
  /usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
fi

echo "Created: $DMG_PATH"
/usr/bin/shasum -a 256 "$DMG_PATH"
