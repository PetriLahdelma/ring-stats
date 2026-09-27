#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
artifact="${1:-}"
installed_app="${2:-$HOME/Applications/Ring Stats.app}"
output="${3:-}"
test_mode="${RING_STATS_TEST_MODE:-0}"
if [[ "$test_mode" == "1" ]]; then CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"; else CODESIGN_BIN=/usr/bin/codesign; fi
[[ -f "$artifact" && ! -L "$artifact" && -n "$output" ]] || { echo "Usage: $0 <final-dmg> <installed-app> <output-plist>" >&2; exit 1; }
mount_dir=""
cleanup() { if [[ -n "$mount_dir" ]]; then /usr/bin/hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true; /bin/rmdir "$mount_dir" >/dev/null 2>&1 || true; fi; }
trap cleanup EXIT

if [[ "$test_mode" == "1" ]]; then
  [[ -n "${ARTIFACT_APP_PATH:-}" ]] || { echo "error: test artifact app is required" >&2; exit 1; }
  mounted_app="$ARTIFACT_APP_PATH"
else
  /usr/bin/codesign --verify --verbose=2 "$artifact"
  xcrun stapler validate "$artifact"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$artifact"
  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-final-mount.XXXXXX")"
  /usr/bin/hdiutil attach "$artifact" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
  mounted_app="$mount_dir/Ring Stats.app"
fi
[[ -d "$mounted_app" && -d "$installed_app" ]] || { echo "error: mounted or installed app missing" >&2; exit 1; }
"$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$mounted_app"
"$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$installed_app"
mounted_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$mounted_app/Contents/Info.plist")"
installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")"
[[ "$mounted_id" == "com.digitaltableteur.ringstats" && "$installed_id" == "$mounted_id" ]] || { echo "error: bundle identifier mismatch" >&2; exit 1; }
/usr/bin/cmp -s "$mounted_app/Contents/Info.plist" "$installed_app/Contents/Info.plist" || { echo "error: installed Info.plist differs from final artifact" >&2; exit 1; }
mounted_identity="$(mktemp "${TMPDIR:-/tmp}/ring-stats-mounted-identity.XXXXXX")"
installed_identity="$(mktemp "${TMPDIR:-/tmp}/ring-stats-installed-identity.XXXXXX")"
trap 'cleanup; /bin/rm -f "$mounted_identity" "$installed_identity"' EXIT
"$PROJECT_DIR/scripts/bundle_identity.sh" "$mounted_app" "$mounted_identity"
"$PROJECT_DIR/scripts/bundle_identity.sh" "$installed_app" "$installed_identity"
/usr/bin/cmp -s "$mounted_identity" "$installed_identity" || { echo "error: installed bundle differs from final artifact" >&2; exit 1; }
/usr/bin/plutil -create xml1 "$output"
/usr/bin/plutil -insert artifact_sha256 -string "$(/usr/bin/shasum -a 256 "$artifact" | /usr/bin/awk '{print $1}')" "$output"
/usr/bin/plutil -insert bundle_sha256 -string "$(/usr/bin/shasum -a 256 "$mounted_identity" | /usr/bin/awk '{print $1}')" "$output"
/usr/bin/plutil -insert artifact_executable_sha256 -string "$(/usr/bin/shasum -a 256 "$mounted_app/Contents/MacOS/RingStats" | /usr/bin/awk '{print $1}')" "$output"
/usr/bin/plutil -insert installed_bundle_sha256 -string "$(/usr/bin/shasum -a 256 "$installed_identity" | /usr/bin/awk '{print $1}')" "$output"
/usr/bin/plutil -insert installed_executable_sha256 -string "$(/usr/bin/shasum -a 256 "$installed_app/Contents/MacOS/RingStats" | /usr/bin/awk '{print $1}')" "$output"
/usr/bin/plutil -insert bundle_identifier -string "$mounted_id" "$output"
/usr/bin/plutil -insert version -string "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mounted_app/Contents/Info.plist")" "$output"
/usr/bin/plutil -insert build -string "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$mounted_app/Contents/Info.plist")" "$output"
