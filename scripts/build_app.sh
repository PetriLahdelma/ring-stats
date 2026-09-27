#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_NAME="Ring Stats"
EXECUTABLE_NAME="RingStats"
PRODUCT_NAME="RingStats"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_ARCHS="${BUILD_ARCHS:-$(uname -m)}"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
DSYM_DIR="$OUTPUT_DIR/$APP_NAME.app.dSYM"
CONTENTS_DIR="$APP_DIR/Contents"
INSTALL_APP="${INSTALL_APP:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

if [[ ! -f "$PROJECT_DIR/native/Info.plist" ]]; then
  echo "Missing native/Info.plist" >&2
  exit 1
fi

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

source_index="$(mktemp "${TMPDIR:-/tmp}/ring-stats-build-index.XXXXXX")"
trap '/bin/rm -f "$source_index"' EXIT
GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" read-tree HEAD
GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" add -A
FROZEN_SOURCE_TREE="$(GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" write-tree)"
FROZEN_SOURCE_COMMIT="$(/usr/bin/git -C "$PROJECT_DIR" rev-parse HEAD)"
if [[ -z "$(/usr/bin/git -C "$PROJECT_DIR" status --porcelain --untracked-files=normal)" ]]; then FROZEN_SOURCE_CLEAN=true; else FROZEN_SOURCE_CLEAN=false; fi
FROZEN_COMPILER_PATH="$(xcrun --find swiftc)"
FROZEN_COMPILER_VERSION="$("$FROZEN_COMPILER_PATH" --version 2>&1 | /usr/bin/head -n 1)"

binary_paths=()

for architecture in $BUILD_ARCHS; do
  case "$architecture" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
  esac

  scratch_path="$PROJECT_DIR/.build/release-$architecture"
  triple="$architecture-apple-macosx14.0"
  SWIFT_EXEC="$FROZEN_COMPILER_PATH" swift build \
    -c "$CONFIGURATION" \
    --product "$PRODUCT_NAME" \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    -Xswiftc -warnings-as-errors \
    -Xswiftc -g \
    -Xswiftc -file-prefix-map \
    -Xswiftc "$PROJECT_DIR=."

  bin_path="$(SWIFT_EXEC="$FROZEN_COMPILER_PATH" swift build \
    -c "$CONFIGURATION" \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    --show-bin-path)"
  binary_paths+=("$bin_path/$EXECUTABLE_NAME")
done

GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" read-tree HEAD
GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" add -A
[[ "$(GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" write-tree)" == "$FROZEN_SOURCE_TREE" ]] || { echo "Source tree changed during compilation." >&2; exit 1; }

rm -rf "$APP_DIR"
rm -rf "$DSYM_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

if [[ "${#binary_paths[@]}" -eq 1 ]]; then
  /usr/bin/ditto "${binary_paths[0]}" "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
else
  /usr/bin/lipo -create "${binary_paths[@]}" -output "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
fi
/usr/bin/dsymutil "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME" -o "$DSYM_DIR"
while IFS= read -r -d '' yaml; do
  /usr/bin/sed -i '' "s#${PROJECT_DIR//\#/\\#}#.#g" "$yaml"
done < <(/usr/bin/find "$DSYM_DIR" -type f -name '*.yml' -print0)

executable_uuids="$(/usr/bin/dwarfdump --uuid "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort)"
dsym_uuids="$(/usr/bin/dwarfdump --uuid "$DSYM_DIR" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort)"
if [[ "$executable_uuids" != "$dsym_uuids" ]]; then
  echo "Executable and dSYM UUIDs do not match." >&2
  exit 1
fi
for architecture in $BUILD_ARCHS; do
  if [[ "$executable_uuids" != *"$architecture:"* ]]; then
    echo "Missing $architecture UUID in executable/dSYM evidence." >&2
    exit 1
  fi
done
/usr/bin/strip -S -x "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"

/usr/bin/ditto "$PROJECT_DIR/native/Info.plist" "$CONTENTS_DIR/Info.plist"

if [[ -n "$MARKETING_VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
fi

if [[ -d "$PROJECT_DIR/Sources/RingStats/Resources/Assets.xcassets" ]]; then
  asset_info_plist="$(mktemp "${TMPDIR:-/tmp}/ring-stats-assets.plist.XXXXXX")"
  trap 'rm -f "$asset_info_plist"' EXIT
  xcrun actool "$PROJECT_DIR/Sources/RingStats/Resources/Assets.xcassets" \
    --compile "$CONTENTS_DIR/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --include-all-app-icons \
    --bundle-identifier com.digitaltableteur.ringstats \
    --output-partial-info-plist "$asset_info_plist" \
    --output-format human-readable-text >/dev/null
  rm -f "$asset_info_plist"
  trap - EXIT

  icon_parent="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-icon.XXXXXX")"
  iconset_dir="$icon_parent/AppIcon.iconset"
  trap 'rm -rf "$icon_parent"' EXIT
  mkdir "$iconset_dir"
  /bin/cp "$PROJECT_DIR/Sources/RingStats/Resources/Assets.xcassets/AppIcon.appiconset/"*.png "$iconset_dir/"
  /usr/bin/iconutil -c icns "$iconset_dir" -o "$CONTENTS_DIR/Resources/AppIcon.icns"
  rm -rf "$icon_parent"
  trap - EXIT
fi

# The App Sandbox needs a container-migration manifest so the first
# sandboxed launch moves existing preferences into the container.
/bin/cp "$PROJECT_DIR/native/container-migration.plist" "$CONTENTS_DIR/Resources/container-migration.plist"

ENTITLEMENTS="$PROJECT_DIR/native/RingStats.entitlements"
sign_target() {
  local target="$1"
  if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS" "$target"
  else
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --entitlements "$ENTITLEMENTS" \
      --sign "$CODESIGN_IDENTITY" \
      "$target"
  fi
}

sign_target "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
sign_target "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" read-tree HEAD
GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" add -A
[[ "$(GIT_INDEX_FILE="$source_index" /usr/bin/git -C "$PROJECT_DIR" write-tree)" == "$FROZEN_SOURCE_TREE" ]] || { echo "Source tree changed during application assembly." >&2; exit 1; }
FROZEN_SOURCE_TREE="$FROZEN_SOURCE_TREE" FROZEN_SOURCE_COMMIT="$FROZEN_SOURCE_COMMIT" \
FROZEN_SOURCE_CLEAN="$FROZEN_SOURCE_CLEAN" FROZEN_COMPILER_PATH="$FROZEN_COMPILER_PATH" \
FROZEN_COMPILER_VERSION="$FROZEN_COMPILER_VERSION" APP_DIR="$APP_DIR" DSYM_DIR="$DSYM_DIR" \
  "$PROJECT_DIR/scripts/emit_candidate_manifest.sh"
"$PROJECT_DIR/scripts/verify_candidate_manifest.sh"

echo "Built and signed: $APP_DIR"
echo "Retained symbols: $DSYM_DIR"
echo "Architectures: $(/usr/bin/lipo -archs "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME")"

case "$INSTALL_APP" in
0) ;;
1)
  "$PROJECT_DIR/scripts/install_local_candidate.sh" "$APP_DIR"
  ;;
*)
  echo "INSTALL_APP must be 0 or 1." >&2
  exit 1
  ;;
esac
