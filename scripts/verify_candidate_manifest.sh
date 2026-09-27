#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
if [[ "${RING_STATS_TEST_MODE:-0}" == "1" && -n "${TEST_PROJECT_DIR:-}" ]]; then
  PROJECT_DIR="$(cd "$TEST_PROJECT_DIR" && pwd -P)"
fi
MANIFEST_PATH="${1:-$PROJECT_DIR/dist/candidate-manifest.json}"
APP_DIR="${2:-$PROJECT_DIR/dist/Ring Stats.app}"
DSYM_DIR="${3:-$PROJECT_DIR/dist/Ring Stats.app.dSYM}"
MANIFEST_HASH_PATH="${MANIFEST_HASH_PATH:-${MANIFEST_PATH%.*}.sha256}"
EXECUTABLE="$APP_DIR/Contents/MacOS/RingStats"

fail() { echo "error: $*" >&2; exit 1; }
read_field() { /usr/bin/plutil -extract "$2" raw "$1" 2>/dev/null || true; }
canonical_path() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
working_tree_hash() {
  local index
  index="$(mktemp "${TMPDIR:-/tmp}/ring-stats-manifest-index.XXXXXX")"
  GIT_INDEX_FILE="$index" /usr/bin/git -C "$PROJECT_DIR" read-tree HEAD
  GIT_INDEX_FILE="$index" /usr/bin/git -C "$PROJECT_DIR" add -A
  GIT_INDEX_FILE="$index" /usr/bin/git -C "$PROJECT_DIR" write-tree
  /bin/rm -f "$index"
}

for path_value in "$MANIFEST_PATH" "$APP_DIR" "$DSYM_DIR" "$MANIFEST_HASH_PATH"; do
  [[ -n "$path_value" && "$path_value" != "/" && ! "$path_value" =~ [[:cntrl:]] ]] || fail "Unsafe manifest verification path"
  [[ ! -L "$path_value" ]] || fail "Manifest evidence paths must not be symbolic links: $path_value"
done
[[ -f "$MANIFEST_PATH" && -f "$MANIFEST_HASH_PATH" ]] || fail "Missing manifest or manifest checksum"
[[ -x "$EXECUTABLE" && -d "$DSYM_DIR" ]] || fail "Missing candidate executable or dSYM"
if [[ "${RING_STATS_TEST_MODE:-0}" != "1" ]]; then
  [[ "$(canonical_path "$MANIFEST_PATH")" == "$PROJECT_DIR/dist/"* ]] || fail "Manifest must be under dist"
  [[ "$(canonical_path "$APP_DIR")" == "$PROJECT_DIR/dist/"* ]] || fail "Candidate must be under dist"
  [[ "$(canonical_path "$DSYM_DIR")" == "$PROJECT_DIR/dist/"* ]] || fail "dSYM must be under dist"
fi

expected_manifest_hash="$(/usr/bin/awk 'NF {print $1; exit}' "$MANIFEST_HASH_PATH")"
actual_manifest_hash="$(/usr/bin/shasum -a 256 "$MANIFEST_PATH" | /usr/bin/awk '{print $1}')"
[[ "$expected_manifest_hash" =~ ^[0-9a-f]{64}$ && "$expected_manifest_hash" == "$actual_manifest_hash" ]] || fail "Manifest SHA-256 evidence differs"
[[ "$(read_field "$MANIFEST_PATH" schema_version)" == "1" ]] || fail "Unsupported candidate manifest schema"

for field in bundle_identifier source_commit source_tree_hash source_worktree_clean app_binary_sha256 bundle_identity_sha256 version build architectures signature_identity executable_uuids dsym_uuids swift_toolchain xcode_toolchain compiler_path compiler_version verified_at candidate_path; do
  [[ -n "$(read_field "$MANIFEST_PATH" "$field")" ]] || fail "Candidate manifest field is missing: $field"
done

[[ "$(read_field "$MANIFEST_PATH" source_commit)" =~ ^[0-9a-f]{40}$ ]] || fail "Malformed source commit"
[[ "$(read_field "$MANIFEST_PATH" source_tree_hash)" =~ ^[0-9a-f]{40}$ ]] || fail "Malformed source tree"
[[ "$(read_field "$MANIFEST_PATH" app_binary_sha256)" =~ ^[0-9a-f]{64}$ ]] || fail "Malformed binary SHA-256"
[[ "$(read_field "$MANIFEST_PATH" bundle_identifier)" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")" ]] || fail "Bundle identifier differs"
[[ "$(read_field "$MANIFEST_PATH" version)" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" ]] || fail "Version differs"
[[ "$(read_field "$MANIFEST_PATH" build)" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")" ]] || fail "Build differs"
[[ "$(/usr/bin/git -C "$PROJECT_DIR" cat-file -t "$(read_field "$MANIFEST_PATH" source_commit)" 2>/dev/null || true)" == "commit" ]] || fail "Source commit is unavailable"
[[ "$(read_field "$MANIFEST_PATH" source_tree_hash)" == "$(working_tree_hash)" ]] || fail "Source tree differs"
recorded_clean="$(read_field "$MANIFEST_PATH" source_worktree_clean)"
[[ "$recorded_clean" == "true" || "$recorded_clean" == "false" ]] || fail "Worktree cleanliness must be a boolean"

actual_binary_hash="$(/usr/bin/shasum -a 256 "$EXECUTABLE" | /usr/bin/awk '{print $1}')"
[[ "$(read_field "$MANIFEST_PATH" app_binary_sha256)" == "$actual_binary_hash" ]] || fail "Candidate binary differs"
identity_file="$(mktemp "${TMPDIR:-/tmp}/ring-stats-verify-identity.XXXXXX")"
trap '/bin/rm -f "$identity_file"' EXIT
"$SCRIPT_DIR/bundle_identity.sh" "$APP_DIR" "$identity_file"
[[ "$(read_field "$MANIFEST_PATH" bundle_identity_sha256)" == "$(/usr/bin/shasum -a 256 "$identity_file" | /usr/bin/awk '{print $1}')" ]] || fail "Candidate bundle identity differs"
actual_architectures="$(/usr/bin/lipo -archs "$EXECUTABLE" | /usr/bin/tr ' ' '\n' | LC_ALL=C /usr/bin/sort | /usr/bin/paste -sd, -)"
[[ "$(read_field "$MANIFEST_PATH" architectures)" == "$actual_architectures" ]] || fail "Architectures differ"
codesign_details="$(/usr/bin/codesign -dvvv "$APP_DIR" 2>&1)"
signature_identity="$(printf '%s\n' "$codesign_details" | /usr/bin/awk -F= '/^Authority=/{print $2; exit}')"
[[ -n "$signature_identity" ]] || signature_identity="$(printf '%s\n' "$codesign_details" | /usr/bin/awk -F= '/^Signature=/{print $2; exit}')"
[[ "$(read_field "$MANIFEST_PATH" signature_identity)" == "$signature_identity" ]] || fail "Signature identity differs"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
actual_compiler="$(xcrun --find swiftc)"
[[ "$(read_field "$MANIFEST_PATH" compiler_path)" == "$actual_compiler" ]] || fail "Compiler path differs"
[[ "$(read_field "$MANIFEST_PATH" compiler_version)" == "$("$actual_compiler" --version 2>&1 | /usr/bin/head -n 1)" ]] || fail "Compiler version differs"
executable_uuids="$(/usr/bin/dwarfdump --uuid "$EXECUTABLE" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort | /usr/bin/paste -sd, -)"
dsym_uuids="$(/usr/bin/dwarfdump --uuid "$DSYM_DIR" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort | /usr/bin/paste -sd, -)"
[[ "$executable_uuids" == "$dsym_uuids" ]] || fail "Executable and dSYM UUIDs differ"
[[ "$(read_field "$MANIFEST_PATH" executable_uuids)" == "$executable_uuids" && "$(read_field "$MANIFEST_PATH" dsym_uuids)" == "$dsym_uuids" ]] || fail "Manifest UUID evidence differs"
while IFS= read -r -d '' symbol_file; do
  findings="$(/usr/bin/strings -a "$symbol_file" | /usr/bin/grep -E "$PROJECT_DIR|CLIENT_SECRET|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY" || true)"
  [[ -z "$findings" ]] || fail "Sensitive or absolute workspace path found in dSYM: $symbol_file"
done < <(/usr/bin/find "$DSYM_DIR" -type f -print0)

manifest_candidate="$(read_field "$MANIFEST_PATH" candidate_path)"
[[ "$manifest_candidate" == "$(canonical_path "$APP_DIR")" ]] || fail "Candidate path differs or is not canonical"
timestamp="$(read_field "$MANIFEST_PATH" verified_at)"
[[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail "Malformed verification timestamp"
timestamp_epoch="$(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$timestamp" '+%s' 2>/dev/null || true)"
[[ -n "$timestamp_epoch" && "$timestamp_epoch" -le "$(/bin/date -u '+%s')" ]] || fail "Invalid or future verification timestamp"

echo "Verified candidate manifest schema 1: $MANIFEST_PATH ($actual_manifest_hash)"
