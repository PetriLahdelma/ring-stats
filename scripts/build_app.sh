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
CONTENTS_DIR="$APP_DIR/Contents"
INSTALL_APP="${INSTALL_APP:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
USER_APPLICATIONS_DIR="$HOME/Applications"
INSTALLED_APP_DIR="$USER_APPLICATIONS_DIR/$APP_NAME.app"

if [[ ! -f "$PROJECT_DIR/native/Info.plist" ]]; then
  echo "Missing native/Info.plist" >&2
  exit 1
fi

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

binary_paths=()

for architecture in $BUILD_ARCHS; do
  case "$architecture" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
  esac

  scratch_path="$PROJECT_DIR/.build/release-$architecture"
  triple="$architecture-apple-macosx14.0"
  swift build \
    -c "$CONFIGURATION" \
    --product "$PRODUCT_NAME" \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    -Xswiftc -gnone \
    -Xswiftc -file-prefix-map \
    -Xswiftc "$PROJECT_DIR=."

  bin_path="$(swift build \
    -c "$CONFIGURATION" \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    --show-bin-path)"
  binary_paths+=("$bin_path/$EXECUTABLE_NAME")
done

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

if [[ "${#binary_paths[@]}" -eq 1 ]]; then
  /usr/bin/ditto "${binary_paths[0]}" "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
else
  /usr/bin/lipo -create "${binary_paths[@]}" -output "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
fi
/usr/bin/strip -S -x "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"

/usr/bin/ditto "$PROJECT_DIR/native/Info.plist" "$CONTENTS_DIR/Info.plist"

if [[ -n "$MARKETING_VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
fi

if [[ -d "$PROJECT_DIR/Sources/RingStats/Resources/Assets.xcassets" ]]; then
  xcrun actool "$PROJECT_DIR/Sources/RingStats/Resources/Assets.xcassets" \
    --compile "$CONTENTS_DIR/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --output-format human-readable-text >/dev/null
fi

sign_target() {
  local target="$1"
  if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign - "$target"
  else
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$CODESIGN_IDENTITY" \
      "$target"
  fi
}

sign_target "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
sign_target "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Built and signed: $APP_DIR"
echo "Architectures: $(/usr/bin/lipo -archs "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME")"

if [[ "$INSTALL_APP" == "1" ]]; then
  mkdir -p "$USER_APPLICATIONS_DIR"
  rm -rf "$INSTALLED_APP_DIR"
  /usr/bin/ditto "$APP_DIR" "$INSTALLED_APP_DIR"
  /usr/bin/touch "$INSTALLED_APP_DIR"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALLED_APP_DIR"
  /usr/bin/mdimport -i "$INSTALLED_APP_DIR" >/dev/null 2>&1 || true
  echo "Installed and registered: $INSTALLED_APP_DIR"
fi
