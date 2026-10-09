#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
if [[ "${RING_STATS_TEST_MODE:-0}" == "1" && -n "${TEST_PROJECT_DIR:-}" ]]; then
  PROJECT_DIR="$(cd "$TEST_PROJECT_DIR" && pwd -P)"
fi
kind="${1:-}"
target="${2:-}"
message="${3:-}"
if [[ "${RING_STATS_TEST_MODE:-0}" == "1" ]]; then
  APP_PATH="${APP_PATH:-$HOME/Applications/Ring Stats.app}"
  APPROVAL_DIR="${APPROVAL_DIR:-$PROJECT_DIR/.omx/approvals}"
  ARTIFACT_APP_PATH="${ARTIFACT_APP_PATH:-}"
  CANDIDATE_MANIFEST="${CANDIDATE_MANIFEST:-$PROJECT_DIR/dist/candidate-manifest.json}"
else
  APP_PATH="$HOME/Applications/Ring Stats.app"
  APPROVAL_DIR="$PROJECT_DIR/.omx/approvals"
  ARTIFACT_APP_PATH=""
  CANDIDATE_MANIFEST="$PROJECT_DIR/dist/candidate-manifest.json"
fi

[[ -n "$message" ]] || fail "The exact explicit user approval message is required"
/bin/mkdir -p "$APPROVAL_DIR"
[[ ! -L "$APPROVAL_DIR" ]] || fail "Approval directory must not be a symbolic link"
canonical_approval_dir="$(cd "$APPROVAL_DIR" && pwd -P)"
[[ "$canonical_approval_dir" == "$APPROVAL_DIR" ]] || fail "Approval directory must be canonical"
temporary="$(mktemp "$APPROVAL_DIR/.approval.XXXXXX.plist")"
cleanup() { /bin/rm -f "$temporary"; }
trap cleanup EXIT
/usr/bin/plutil -create xml1 "$temporary"
/usr/bin/plutil -insert schema_version -integer 1 "$temporary"
/usr/bin/plutil -insert approval_kind -string "$kind" "$temporary"
/usr/bin/plutil -insert explicit_user_message -string "$message" "$temporary"
/usr/bin/plutil -insert approved_at -string "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$temporary"

case "$kind" in
  gate-a)
    [[ -f "$target" ]] || fail "Missing candidate manifest: $target"
    [[ ! -L "$target" ]] || fail "Candidate manifest must not be a symbolic link"
    if [[ "${RING_STATS_TEST_MODE:-0}" != "1" ]]; then
      "$SCRIPT_DIR/verify_candidate_manifest.sh" "$target" >/dev/null
    fi
    tree_hash="$(/usr/bin/plutil -extract source_tree_hash raw "$target")"
    binary_hash="$(/usr/bin/plutil -extract app_binary_sha256 raw "$target")"
    /usr/bin/plutil -insert source_tree_hash -string "$tree_hash" "$temporary"
    /usr/bin/plutil -insert app_binary_sha256 -string "$binary_hash" "$temporary"
    /usr/bin/plutil -insert manifest_sha256 -string "$(/usr/bin/shasum -a 256 "$target" | /usr/bin/awk '{print $1}')" "$temporary"
    marker="$APPROVAL_DIR/gate-a.json"
    ;;
  gate-b)
    [[ -f "$target" ]] || fail "Missing final artifact: $target"
    [[ -f "$CANDIDATE_MANIFEST" && ! -L "$CANDIDATE_MANIFEST" ]] || fail "Missing safe final candidate manifest: $CANDIDATE_MANIFEST"
    if [[ "${RING_STATS_TEST_MODE:-0}" != "1" ]]; then
      "$SCRIPT_DIR/verify_candidate_manifest.sh" "$CANDIDATE_MANIFEST" >/dev/null
    fi
    gate_a_marker="$APPROVAL_DIR/gate-a.json"
    [[ -f "$gate_a_marker" && ! -L "$gate_a_marker" ]] || fail "Gate B requires an existing Gate A marker"
    [[ "$(/usr/bin/plutil -extract schema_version raw "$gate_a_marker" 2>/dev/null || true)" == "1" && "$(/usr/bin/plutil -extract approval_kind raw "$gate_a_marker" 2>/dev/null || true)" == "gate-a" ]] || fail "Gate A marker schema is invalid"
    [[ -n "$(/usr/bin/plutil -extract explicit_user_message raw "$gate_a_marker" 2>/dev/null || true)" ]] || fail "Gate A marker lacks explicit approval text"
    gate_a_time="$(/usr/bin/plutil -extract approved_at raw "$gate_a_marker" 2>/dev/null || true)"
    gate_a_epoch="$(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$gate_a_time" '+%s' 2>/dev/null || true)"
    [[ -n "$gate_a_epoch" && "$gate_a_epoch" -le "$(/bin/date -u '+%s')" ]] || fail "Gate A marker time is invalid"
    gate_a_manifest_hash="$(/usr/bin/plutil -extract manifest_sha256 raw "$gate_a_marker" 2>/dev/null || true)"
    gate_a_archive="$PROJECT_DIR/dist/candidates/$gate_a_manifest_hash"
    "$SCRIPT_DIR/verify_candidate_archive.sh" "$gate_a_archive" "$gate_a_manifest_hash" >/dev/null
    gate_a_tree="$(/usr/bin/plutil -extract source_tree_hash raw "$gate_a_marker")"
    [[ "$gate_a_tree" == "$(/usr/bin/plutil -extract source_tree_hash raw "$gate_a_archive/candidate-manifest.json")" ]] || fail "Gate A marker differs from immutable evidence"
    [[ "$(/usr/bin/plutil -extract app_binary_sha256 raw "$gate_a_marker")" == "$(/usr/bin/plutil -extract app_binary_sha256 raw "$gate_a_archive/candidate-manifest.json")" ]] || fail "Gate A binary differs from immutable evidence"
    [[ "$gate_a_tree" == "$(/usr/bin/plutil -extract source_tree_hash raw "$CANDIDATE_MANIFEST")" ]] || fail "Final manifest source tree differs from Gate A"
    identity_plist="$(mktemp "${TMPDIR:-/tmp}/ring-stats-gate-b.XXXXXX.plist")"
    trap 'cleanup; /bin/rm -f "$identity_plist"' EXIT
    "$SCRIPT_DIR/verify_final_artifact.sh" "$target" "$APP_PATH" "$identity_plist" >/dev/null
    [[ "$(/usr/bin/plutil -extract bundle_identity_sha256 raw "$CANDIDATE_MANIFEST")" == "$(/usr/bin/plutil -extract bundle_sha256 raw "$identity_plist")" ]] || fail "Final manifest bundle identity differs from artifact"
    [[ "$(/usr/bin/plutil -extract app_binary_sha256 raw "$CANDIDATE_MANIFEST")" == "$(/usr/bin/plutil -extract artifact_executable_sha256 raw "$identity_plist")" ]] || fail "Final manifest executable differs from artifact"
    for metadata_field in bundle_identifier version build; do
      [[ "$(/usr/bin/plutil -extract "$metadata_field" raw "$CANDIDATE_MANIFEST")" == "$(/usr/bin/plutil -extract "$metadata_field" raw "$identity_plist")" ]] || fail "Final manifest metadata differs: $metadata_field"
    done
    for field_name in artifact_sha256 bundle_sha256 artifact_executable_sha256 installed_bundle_sha256 installed_executable_sha256 bundle_identifier version build; do
      /usr/bin/plutil -insert "$field_name" -string "$(/usr/bin/plutil -extract "$field_name" raw "$identity_plist")" "$temporary"
    done
    /usr/bin/plutil -insert source_tree_hash -string "$(/usr/bin/plutil -extract source_tree_hash raw "$CANDIDATE_MANIFEST")" "$temporary"
    /usr/bin/plutil -insert manifest_sha256 -string "$(/usr/bin/shasum -a 256 "$CANDIDATE_MANIFEST" | /usr/bin/awk '{print $1}')" "$temporary"
    marker="$APPROVAL_DIR/gate-b.json"
    ;;
  *) fail "Usage: $0 gate-a <candidate-manifest> <exact-user-message> | gate-b <artifact> <exact-user-message>" ;;
esac

/usr/bin/plutil -convert json -o "$marker" "$temporary"
echo "Recorded $kind approval: $marker"
