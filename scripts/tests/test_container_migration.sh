#!/bin/bash
# Verifies that a container-migration manifest in the same form as
# native/container-migration.plist moves files into a new App Sandbox
# container on first launch. A throwaway probe app with its own bundle
# identifier migrates a dummy preferences file and folder; the app's real
# preferences are never touched.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-migration-probe.XXXXXX")"
PROBE_ID="com.digitaltableteur.ringstats.migration-probe"
CONTAINER="$HOME/Library/Containers/$PROBE_ID"
PREFS="$HOME/Library/Preferences/$PROBE_ID.plist"
SUPPORT="$HOME/Library/Application Support/Ring Stats Migration Probe"
remove_probe_state() {
  /bin/rm -rf "$SUPPORT" "$PREFS"
  /bin/rm -rf "$CONTAINER" 2>/dev/null || true
}
cleanup() {
  /bin/rm -rf "$WORK"
  remove_probe_state
}
trap cleanup EXIT
remove_probe_state

# Same shape as the production manifest, pointed at probe-owned paths.
/usr/bin/sed \
  -e "s#com.digitaltableteur.ringstats.plist#$PROBE_ID.plist#" \
  -e "s#Application Support/Ring Stats Public#Application Support/Ring Stats Migration Probe#" \
  "$PROJECT_DIR/native/container-migration.plist" > "$WORK/container-migration.plist"
/usr/bin/grep -q "$PROBE_ID.plist" "$WORK/container-migration.plist" || { echo "FAIL: manifest shape changed" >&2; exit 1; }

/usr/bin/defaults write "$PROBE_ID" probe-key -string migrated
/bin/mkdir -p "$SUPPORT/Legacy Secrets"
printf 'probe' > "$SUPPORT/Legacy Secrets/marker.json"

app="$WORK/Probe.app"
/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
/bin/cp "$WORK/container-migration.plist" "$app/Contents/Resources/"
/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "$PROBE_ID" "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string probe "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let marker = support.appendingPathComponent("Ring Stats Migration Probe/Legacy Secrets/marker.json")
print("home=\(NSHomeDirectory())")
print("marker=\(FileManager.default.fileExists(atPath: marker.path))")
print("pref=\(UserDefaults.standard.string(forKey: "probe-key") ?? "missing")")
SWIFT
/usr/bin/xcrun swiftc -O "$WORK/main.swift" -o "$app/Contents/MacOS/probe"
/usr/bin/codesign --force --sign - --entitlements "$PROJECT_DIR/native/RingStats.entitlements" "$app"

output="$("$app/Contents/MacOS/probe")"
echo "$output"
[[ "$output" == *"home=$CONTAINER"* ]] || { echo "FAIL: probe did not run in its container" >&2; exit 1; }
[[ "$output" == *"marker=true"* ]] || { echo "FAIL: Application Support folder was not migrated" >&2; exit 1; }
[[ "$output" == *"pref=migrated"* ]] || { echo "FAIL: preferences were not migrated" >&2; exit 1; }
[[ ! -e "$SUPPORT" ]] || { echo "FAIL: migration copied instead of moving the folder" >&2; exit 1; }
echo "Container migration tests passed"
