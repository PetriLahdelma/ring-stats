#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/Ring Stats.app"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/native/Info.plist")"
SOURCE_BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_DIR/native/Info.plist")"
VERSION="${MARKETING_VERSION:-$SOURCE_VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-$SOURCE_BUILD_NUMBER}"
DMG_PATH="$OUTPUT_DIR/Ring-Stats-$VERSION.dmg"
METADATA_DIR="$OUTPUT_DIR/release-metadata"

: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${APPLE_NOTARY_PROFILE:?Set APPLE_NOTARY_PROFILE to a notarytool Keychain profile}"

if [[ "$VERSION" != "$SOURCE_VERSION" || "$BUILD_NUMBER" != "$SOURCE_BUILD_NUMBER" ]]; then
  echo "Release version overrides must match native/Info.plist." >&2
  exit 1
fi

if [[ -n "$(/usr/bin/git -C "$PROJECT_DIR" status --porcelain --untracked-files=normal)" ]]; then
  echo "Release signing requires a clean working tree." >&2
  exit 1
fi

exact_tag="$(/usr/bin/git -C "$PROJECT_DIR" describe --exact-match --tags HEAD 2>/dev/null || true)"
if [[ -z "$exact_tag" || "$exact_tag" != v* ]]; then
  echo "Release signing requires HEAD to be an exact v* tag." >&2
  exit 1
fi
if [[ "$(/usr/bin/git -C "$PROJECT_DIR" cat-file -t "$exact_tag")" != "tag" ]]; then
  echo "Release tag must be annotated: $exact_tag" >&2
  exit 1
fi
tag_version="${exact_tag#v}"
if [[ "$tag_version" != "$VERSION" ]]; then
  echo "Tag version $tag_version does not match bundle version $VERSION." >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "CFBundleVersion must be a positive integer: $BUILD_NUMBER" >&2
  exit 1
fi

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
MARKETING_VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
"$PROJECT_DIR/scripts/create_dmg.sh"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
DMG_PATH="$DMG_PATH" "$PROJECT_DIR/scripts/verify_release_artifacts.sh"

if [[ -d "$METADATA_DIR" ]]; then
  /bin/rm -rf "$METADATA_DIR"
fi
/bin/mkdir -p "$METADATA_DIR"
/usr/bin/git -C "$PROJECT_DIR" show -s --format=fuller HEAD > "$METADATA_DIR/source-commit.txt"
/usr/bin/git -C "$PROJECT_DIR" for-each-ref "refs/tags/$exact_tag" \
  --format='tag=%(refname:short)%0atag_object=%(objectname)%0acreator=%(creator)%0asubject=%(subject)' \
  > "$METADATA_DIR/source-tag.txt"
/usr/bin/swift --version > "$METADATA_DIR/toolchain.txt"
/usr/bin/xcodebuild -version >> "$METADATA_DIR/toolchain.txt"
/usr/bin/swift package --package-path "$PROJECT_DIR" show-dependencies --format json \
  > "$METADATA_DIR/source-dependencies.json"
/usr/bin/codesign -dvvv "$APP_DIR" 2> "$METADATA_DIR/codesign-app.txt"
/usr/bin/codesign -dvvv "$DMG_PATH" 2> "$METADATA_DIR/codesign-dmg.txt"

set +e
xcrun notarytool submit \
  "$DMG_PATH" \
  --keychain-profile "$APPLE_NOTARY_PROFILE" \
  --wait \
  --output-format json > "$METADATA_DIR/notary-submission.json"
submit_status=$?
set -e

notary_status="$(/usr/bin/plutil -extract status raw "$METADATA_DIR/notary-submission.json" 2>/dev/null || true)"
submission_id="$(/usr/bin/plutil -extract id raw "$METADATA_DIR/notary-submission.json" 2>/dev/null || true)"
if [[ -n "$submission_id" ]]; then
  xcrun notarytool log "$submission_id" \
    --keychain-profile "$APPLE_NOTARY_PROFILE" \
    "$METADATA_DIR/notary-log.json" || true
fi
if [[ "$submit_status" -ne 0 || "$notary_status" != "Accepted" ]]; then
  echo "Notarization failed with status: ${notary_status:-unknown}" >&2
  echo "Notarization evidence retained in: $METADATA_DIR" >&2
  exit 1
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
/usr/sbin/spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  "$DMG_PATH"

echo "Signed, notarized, and stapled: $DMG_PATH"
(cd "$OUTPUT_DIR" && /usr/bin/shasum -a 256 "Ring-Stats-$VERSION.dmg") \
  > "$METADATA_DIR/Ring-Stats-$VERSION.dmg.sha256"
/usr/bin/shasum -a 256 "$APP_DIR/Contents/MacOS/RingStats" > "$METADATA_DIR/RingStats-binary.sha256"
DMG_PATH="$DMG_PATH" "$PROJECT_DIR/scripts/verify_release_artifacts.sh"
echo "Release evidence retained in: $METADATA_DIR"
