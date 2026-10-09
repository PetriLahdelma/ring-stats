#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_DIR="${APP_DIR:-$PROJECT_DIR/dist/Ring Stats.app}"
DMG_PATH="${DMG_PATH:-}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.digitaltableteur.ringstats}"
EXPECTED_ARCHS="${EXPECTED_ARCHS:-arm64 x86_64}"
EXECUTABLE="$APP_DIR/Contents/MacOS/RingStats"
DSYM_DIR="${DSYM_DIR:-$PROJECT_DIR/dist/Ring Stats.app.dSYM}"
MANIFEST_PATH="${MANIFEST_PATH:-$PROJECT_DIR/dist/candidate-manifest.json}"

fail() {
  echo "error: $*" >&2
  exit 1
}

verify_disk_image() {
  local disk_image="$1"
  local attempt output
  for attempt in 1 2 3; do
    if output="$(/usr/bin/hdiutil verify "$disk_image" 2>&1)"; then
      echo "$output"
      return 0
    fi
    if [[ "$output" != *"Resource temporarily unavailable"* || "$attempt" -eq 3 ]]; then
      echo "$output" >&2
      return 1
    fi
    /bin/sleep 1
  done
}

[[ -d "$APP_DIR" ]] || fail "Missing application bundle: $APP_DIR"
[[ -x "$EXECUTABLE" ]] || fail "Missing executable: $EXECUTABLE"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || fail "Unexpected bundle identifier: $bundle_id"

short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
[[ -n "$short_version" && -n "$build_version" ]] || fail "Missing bundle version metadata"

actual_archs="$(/usr/bin/lipo -archs "$EXECUTABLE")"
for architecture in $EXPECTED_ARCHS; do
  [[ " $actual_archs " == *" $architecture "* ]] || fail "Missing architecture $architecture ($actual_archs)"
done

[[ -d "$DSYM_DIR" ]] || fail "Missing dSYM bundle: $DSYM_DIR"
executable_uuids="$(/usr/bin/dwarfdump --uuid "$EXECUTABLE" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort)"
dsym_uuids="$(/usr/bin/dwarfdump --uuid "$DSYM_DIR" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort)"
[[ "$executable_uuids" == "$dsym_uuids" ]] || fail "Executable and dSYM UUIDs differ"

[[ -f "$MANIFEST_PATH" ]] || fail "Missing candidate manifest: $MANIFEST_PATH"
"$PROJECT_DIR/scripts/verify_candidate_manifest.sh" "$MANIFEST_PATH" "$APP_DIR" "$DSYM_DIR"
manifest_binary_hash="$(/usr/bin/plutil -extract app_binary_sha256 raw "$MANIFEST_PATH")"
actual_binary_hash="$(/usr/bin/shasum -a 256 "$EXECUTABLE" | /usr/bin/awk '{print $1}')"
[[ "$manifest_binary_hash" == "$actual_binary_hash" ]] || fail "Candidate manifest binary hash differs"
[[ "$(/usr/bin/plutil -extract executable_uuids raw "$MANIFEST_PATH")" == "$(printf '%s\n' "$executable_uuids" | /usr/bin/paste -sd, -)" ]] || fail "Candidate manifest UUID evidence differs"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
[[ -f "$APP_DIR/Contents/Resources/AppIcon.icns" ]] || fail "AppIcon.icns was not compiled into the bundle"
[[ -f "$APP_DIR/Contents/Resources/container-migration.plist" ]] || fail "container-migration.plist is missing from the bundle"
intents_metadata="$APP_DIR/Contents/Resources/Metadata.appintents/extract.actionsdata"
[[ -f "$intents_metadata" ]] || fail "App Intents metadata is missing, so Shortcuts cannot find the actions"
for intent in GetRingStatIntent GetRingBatteryIntent; do
  /usr/bin/grep -q "\"$intent\"" "$intents_metadata" || fail "App Intents metadata does not list $intent"
done
entitlements_plist="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/ring-stats-entitlements.XXXXXX")"
/usr/bin/codesign -d --entitlements - --xml "$APP_DIR" > "$entitlements_plist" 2>/dev/null \
  || fail "Could not read the signed entitlements"
entitlement_value() {
  # plutil key paths split on dots, so escape the dots in entitlement names.
  /usr/bin/plutil -extract "${1//./\\.}" raw -o - "$entitlements_plist" 2>/dev/null || echo absent
}
for entitlement in \
  com.apple.security.app-sandbox \
  com.apple.security.network.client \
  com.apple.security.network.server \
  com.apple.security.files.user-selected.read-write; do
  [[ "$(entitlement_value "$entitlement")" == "true" ]] || fail "Entitlement is not true: $entitlement"
done
for entitlement in com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.get-task-allow; do
  [[ "$(entitlement_value "$entitlement")" == "absent" ]] || fail "Unexpected entitlement: $entitlement"
done
/bin/rm -f "$entitlements_plist"

# A Developer ID build must carry the hardened runtime that SECURITY.md and
# THREAT_MODEL.md promise. Notarization would refuse it too, but only after
# Gate A has approved the build.
# Captured first: piping codesign into grep -q trips pipefail on SIGPIPE.
signature_details="$(/usr/bin/codesign -dvv "$APP_DIR" 2>&1 || true)"
if [[ "$signature_details" == *"Authority=Developer ID Application"* ]]; then
  [[ "$signature_details" == *"flags="*"(runtime)"* ]] \
    || fail "Hardened runtime is not enabled on the Developer ID-signed app"
fi

scan_artifact() {
  local target="$1"
  local findings
  findings="$(/usr/bin/strings -a "$target" | /usr/bin/grep -E '/Users/[^/]+/|CLIENT_SECRET|APPLE_NOTARY_PROFILE|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' || true)"
  [[ -z "$findings" ]] || {
    echo "$findings" >&2
    fail "Potential workspace path or secret material found in $target"
  }
}

scan_bundle() {
  local bundle="$1"
  while IFS= read -r -d '' file; do
    scan_artifact "$file"
  done < <(/usr/bin/find "$bundle/Contents" -type f -print0)
}

scan_bundle "$APP_DIR"

if [[ -n "$DMG_PATH" ]]; then
  [[ -f "$DMG_PATH" ]] || fail "Missing disk image: $DMG_PATH"
  scan_artifact "$DMG_PATH"
  verify_disk_image "$DMG_PATH" >/dev/null

  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-mount.XXXXXX")"
  cleanup() {
    /usr/bin/hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
    /bin/rmdir "$mount_dir" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT
  /usr/bin/hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
  [[ -d "$mount_dir/Ring Stats.app" ]] || fail "DMG does not contain Ring Stats.app"
  [[ -L "$mount_dir/Applications" ]] || fail "DMG does not contain the Applications shortcut"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$mount_dir/Ring Stats.app"
  scan_bundle "$mount_dir/Ring Stats.app"
  cleanup
  trap - EXIT
fi

echo "Verified Ring Stats $short_version ($build_version), bundle $bundle_id, architectures: $actual_archs"
