#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib/common.sh"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_DIR="${APP_DIR:-$PROJECT_DIR/dist/Ring Stats.app}"
DSYM_DIR="${DSYM_DIR:-$PROJECT_DIR/dist/Ring Stats.app.dSYM}"
MANIFEST_PATH="${MANIFEST_PATH:-$PROJECT_DIR/dist/candidate-manifest.json}"
MANIFEST_HASH_PATH="${MANIFEST_HASH_PATH:-$PROJECT_DIR/dist/candidate-manifest.sha256}"
EXECUTABLE="$APP_DIR/Contents/MacOS/RingStats"


[[ -x "$EXECUTABLE" ]] || fail "Missing candidate executable: $EXECUTABLE"
[[ -d "$DSYM_DIR" ]] || fail "Missing candidate dSYM: $DSYM_DIR"

temporary_index="$(mktemp "${TMPDIR:-/tmp}/ring-stats-index.XXXXXX")"
manifest_plist="$(mktemp "${TMPDIR:-/tmp}/ring-stats-manifest.plist.XXXXXX")"
cleanup() {
  /bin/rm -f "$temporary_index" "$manifest_plist"
  [[ -z "${bundle_identity_file:-}" ]] || /bin/rm -f "$bundle_identity_file"
  [[ -z "${dsym_identity_file:-}" ]] || /bin/rm -f "$dsym_identity_file"
}
trap cleanup EXIT

GIT_INDEX_FILE="$temporary_index" /usr/bin/git -C "$PROJECT_DIR" read-tree HEAD
GIT_INDEX_FILE="$temporary_index" /usr/bin/git -C "$PROJECT_DIR" add -A
source_tree_hash="${FROZEN_SOURCE_TREE:-$(GIT_INDEX_FILE="$temporary_index" /usr/bin/git -C "$PROJECT_DIR" write-tree)}"
source_commit="${FROZEN_SOURCE_COMMIT:-$(/usr/bin/git -C "$PROJECT_DIR" rev-parse HEAD)}"
binary_hash="$(/usr/bin/shasum -a 256 "$EXECUTABLE" | /usr/bin/awk '{print $1}')"
bundle_identity_file="$(mktemp "${TMPDIR:-/tmp}/ring-stats-bundle-identity.XXXXXX")"
"$PROJECT_DIR/scripts/bundle_identity.sh" "$APP_DIR" "$bundle_identity_file"
bundle_identity_hash="$(/usr/bin/shasum -a 256 "$bundle_identity_file" | /usr/bin/awk '{print $1}')"
dsym_identity_file="$(mktemp "${TMPDIR:-/tmp}/ring-stats-dsym-identity.XXXXXX")"
"$PROJECT_DIR/scripts/bundle_identity.sh" "$DSYM_DIR" "$dsym_identity_file"
dsym_identity_hash="$(/usr/bin/shasum -a 256 "$dsym_identity_file" | /usr/bin/awk '{print $1}')"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
architectures="$(/usr/bin/lipo -archs "$EXECUTABLE" | /usr/bin/tr ' ' '\n' | LC_ALL=C /usr/bin/sort | /usr/bin/paste -sd, -)"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
if [[ -n "${FROZEN_SOURCE_CLEAN:-}" ]]; then
  source_worktree_clean="$FROZEN_SOURCE_CLEAN"
elif [[ -z "$(/usr/bin/git -C "$PROJECT_DIR" status --porcelain --untracked-files=normal)" ]]; then
  source_worktree_clean=true
else
  source_worktree_clean=false
fi

codesign_details="$(/usr/bin/codesign -dvvv "$APP_DIR" 2>&1)"
signature_identity="$(printf '%s\n' "$codesign_details" | /usr/bin/awk -F= '/^Authority=/{print $2; exit}')"
if [[ -z "$signature_identity" ]]; then
  signature_identity="$(printf '%s\n' "$codesign_details" | /usr/bin/awk -F= '/^Signature=/{print $2; exit}')"
fi
[[ -n "$signature_identity" ]] || signature_identity="unknown"

executable_uuids="$(/usr/bin/dwarfdump --uuid "$EXECUTABLE" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort | /usr/bin/paste -sd, -)"
dsym_uuids="$(/usr/bin/dwarfdump --uuid "$DSYM_DIR" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort | /usr/bin/paste -sd, -)"
[[ "$executable_uuids" == "$dsym_uuids" ]] || fail "Executable and dSYM UUIDs differ"

/usr/bin/plutil -create xml1 "$manifest_plist"
/usr/bin/plutil -insert schema_version -integer 1 "$manifest_plist"
/usr/bin/plutil -insert bundle_identifier -string "$bundle_identifier" "$manifest_plist"
/usr/bin/plutil -insert source_commit -string "$source_commit" "$manifest_plist"
/usr/bin/plutil -insert source_tree_hash -string "$source_tree_hash" "$manifest_plist"
/usr/bin/plutil -insert source_worktree_clean -bool "$source_worktree_clean" "$manifest_plist"
/usr/bin/plutil -insert app_binary_sha256 -string "$binary_hash" "$manifest_plist"
/usr/bin/plutil -insert bundle_identity_sha256 -string "$bundle_identity_hash" "$manifest_plist"
/usr/bin/plutil -insert dsym_identity_sha256 -string "$dsym_identity_hash" "$manifest_plist"
/usr/bin/plutil -insert version -string "$version" "$manifest_plist"
/usr/bin/plutil -insert build -string "$build" "$manifest_plist"
/usr/bin/plutil -insert architectures -string "$architectures" "$manifest_plist"
/usr/bin/plutil -insert signature_identity -string "$signature_identity" "$manifest_plist"
/usr/bin/plutil -insert executable_uuids -string "$executable_uuids" "$manifest_plist"
/usr/bin/plutil -insert dsym_uuids -string "$dsym_uuids" "$manifest_plist"
/usr/bin/plutil -insert swift_toolchain -string "$(/usr/bin/swift --version 2>&1 | /usr/bin/head -n 1)" "$manifest_plist"
/usr/bin/plutil -insert xcode_toolchain -string "$(/usr/bin/xcodebuild -version | /usr/bin/paste -sd' ' -)" "$manifest_plist"
/usr/bin/plutil -insert compiler_path -string "${FROZEN_COMPILER_PATH:-$(xcrun --find swiftc)}" "$manifest_plist"
/usr/bin/plutil -insert compiler_version -string "${FROZEN_COMPILER_VERSION:-$("$(xcrun --find swiftc)" --version 2>&1 | /usr/bin/head -n 1)}" "$manifest_plist"
verified_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [[ "${RING_STATS_TEST_MODE:-0}" == "1" && -n "${VERIFIED_AT:-}" ]]; then verified_at="$VERIFIED_AT"; fi
/usr/bin/plutil -insert verified_at -string "$verified_at" "$manifest_plist"
/usr/bin/plutil -insert candidate_path -string "$(cd "$(dirname "$APP_DIR")" && pwd -P)/$(basename "$APP_DIR")" "$manifest_plist"

/bin/mkdir -p "$(dirname "$MANIFEST_PATH")"
/usr/bin/plutil -convert json -o "$MANIFEST_PATH" "$manifest_plist"
/usr/bin/shasum -a 256 "$MANIFEST_PATH" > "$MANIFEST_HASH_PATH"
manifest_hash="$(/usr/bin/awk '{print $1}' "$MANIFEST_HASH_PATH")"
archive_dir="$PROJECT_DIR/dist/candidates/$manifest_hash"
archive_lock="$PROJECT_DIR/dist/candidates/.archive-$manifest_hash.lock"
/bin/mkdir -p "$PROJECT_DIR/dist/candidates"
lock_acquired=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50; do
  if /bin/mkdir "$archive_lock" 2>/dev/null; then lock_acquired=1; break; fi
  /bin/sleep 0.1
done
[[ "$lock_acquired" -eq 1 ]] || fail "Timed out waiting for candidate archive lock"
release_archive_lock() {
  if [[ -n "${staged_archive:-}" && "$staged_archive" == "$PROJECT_DIR/dist/candidates/.candidate-$manifest_hash."* && -d "$staged_archive" ]]; then
    /bin/rm -rf "$staged_archive"
  fi
  /bin/rmdir "$archive_lock" >/dev/null 2>&1 || true
  cleanup
}
trap release_archive_lock EXIT
if [[ -e "$archive_dir" ]]; then
  "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$archive_dir" "$manifest_hash" >/dev/null
else
  staged_archive="$(mktemp -d "$PROJECT_DIR/dist/candidates/.candidate-$manifest_hash.XXXXXX")"
  /bin/cp "$MANIFEST_PATH" "$staged_archive/candidate-manifest.json"
  (cd "$staged_archive" && /usr/bin/shasum -a 256 candidate-manifest.json > candidate-manifest.sha256)
  printf '%s\n' "$executable_uuids" > "$staged_archive/uuids.txt"
  /bin/cp "$bundle_identity_file" "$staged_archive/bundle-identity.txt"
  /bin/cp "$dsym_identity_file" "$staged_archive/dsym-identity.txt"
  /usr/bin/ditto -c -k --keepParent "$DSYM_DIR" "$staged_archive/Ring-Stats.dSYM.zip"
  (cd "$staged_archive" && /usr/bin/shasum -a 256 Ring-Stats.dSYM.zip > Ring-Stats.dSYM.zip.sha256)
  "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$staged_archive" "$manifest_hash" >/dev/null
  /bin/mv "$staged_archive" "$archive_dir"
fi
/bin/rmdir "$archive_lock"
trap cleanup EXIT
echo "Candidate manifest: $MANIFEST_PATH"
echo "Candidate manifest SHA-256: $manifest_hash"
echo "Archived candidate evidence: $archive_dir"
