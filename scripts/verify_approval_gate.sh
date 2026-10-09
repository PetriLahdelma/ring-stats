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


case "$kind" in
  gate-a)
    marker="$APPROVAL_DIR/gate-a.json"
    [[ -f "$target" ]] || fail "Missing candidate manifest: $target"
    [[ ! -L "$target" ]] || fail "Candidate manifest must not be a symbolic link"
    expected="$(read_field "$target" source_tree_hash)"
    field="source_tree_hash"
    ;;
  gate-b)
    marker="$APPROVAL_DIR/gate-b.json"
    [[ -f "$target" ]] || fail "Missing final artifact: $target"
    [[ ! -L "$target" ]] || fail "Final artifact must not be a symbolic link"
    [[ -x "$APP_PATH/Contents/MacOS/RingStats" ]] || fail "Missing installed final app: $APP_PATH"
    expected="$(/usr/bin/shasum -a 256 "$target" | /usr/bin/awk '{print $1}')"
    field="artifact_sha256"
    ;;
  *) fail "Usage: $0 gate-a <candidate-manifest> | gate-b <final-artifact>" ;;
esac

[[ -f "$marker" ]] || fail "Missing $kind user approval marker: $marker"
[[ ! -L "$APPROVAL_DIR" ]] || fail "Approval directory must not be a symbolic link"
[[ "$(cd "$APPROVAL_DIR" && pwd -P)" == "$APPROVAL_DIR" ]] || fail "Approval directory must be canonical"
[[ ! -L "$marker" ]] || fail "Approval marker must not be a symbolic link"
[[ "$(read_field "$marker" schema_version)" == "1" ]] || fail "Unsupported approval marker schema"
[[ "$(read_field "$marker" approval_kind)" == "$kind" ]] || fail "Wrong approval kind in $marker"
[[ -n "$(read_field "$marker" explicit_user_message)" ]] || fail "Approval marker lacks the explicit user message"
approved_at="$(read_field "$marker" approved_at)"
[[ "$approved_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail "Approval marker has malformed approval time"
approved_epoch="$(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$approved_at" '+%s' 2>/dev/null || true)"
[[ -n "$approved_epoch" && "$approved_epoch" -le "$(/bin/date -u '+%s')" ]] || fail "Approval marker time is invalid or in the future"
[[ -n "$expected" && "$(read_field "$marker" "$field")" == "$expected" ]] || fail "$kind approval is stale or identifies different content"

if [[ "$kind" == "gate-a" ]]; then
  if [[ "${RING_STATS_TEST_MODE:-0}" != "1" ]]; then
    "$SCRIPT_DIR/verify_candidate_manifest.sh" "$target" >/dev/null
  fi
  manifest_hash="$(/usr/bin/shasum -a 256 "$target" | /usr/bin/awk '{print $1}')"
  [[ "$(read_field "$marker" manifest_sha256)" == "$manifest_hash" ]] || fail "Candidate manifest differs from Gate A approval"
  if [[ "${RING_STATS_TEST_MODE:-0}" != "1" || -n "${TEST_PROJECT_DIR:-}" ]]; then
    [[ "$expected" == "$(working_tree_hash)" ]] || fail "Candidate manifest does not match the current source tree"
  fi
  candidate_path="$(read_field "$target" candidate_path)"
  if [[ "${RING_STATS_TEST_MODE:-0}" == "1" ]]; then
    [[ -d "$candidate_path" && ! -L "$candidate_path" ]] || fail "Fixture candidate path is missing or linked"
  else
    [[ "$candidate_path" == "$PROJECT_DIR/dist/"* && -d "$candidate_path" && ! -L "$candidate_path" ]] || fail "Candidate path is missing, linked, or outside dist"
    canonical_candidate="$(cd "$(dirname "$candidate_path")" && pwd -P)/$(basename "$candidate_path")"
    [[ "$canonical_candidate" == "$candidate_path" ]] || fail "Candidate path must be canonical"
  fi
  candidate_hash="$(/usr/bin/shasum -a 256 "$candidate_path/Contents/MacOS/RingStats" | /usr/bin/awk '{print $1}')"
  [[ "$candidate_hash" == "$(read_field "$target" app_binary_sha256)" ]] || fail "Candidate binary differs from its manifest"
  [[ "$candidate_hash" == "$(read_field "$marker" app_binary_sha256)" ]] || fail "Candidate binary differs from Gate A approval"
fi

if [[ "$kind" == "gate-b" ]]; then
  [[ -f "$CANDIDATE_MANIFEST" && ! -L "$CANDIDATE_MANIFEST" ]] || fail "Missing safe final candidate manifest: $CANDIDATE_MANIFEST"
  [[ "$(read_field "$marker" source_tree_hash)" == "$(read_field "$CANDIDATE_MANIFEST" source_tree_hash)" ]] || fail "Final source tree differs from Gate B approval"
  [[ "$(read_field "$marker" manifest_sha256)" == "$(/usr/bin/shasum -a 256 "$CANDIDATE_MANIFEST" | /usr/bin/awk '{print $1}')" ]] || fail "Final manifest differs from Gate B approval"
  gate_a_marker="$APPROVAL_DIR/gate-a.json"
  [[ -f "$gate_a_marker" && ! -L "$gate_a_marker" ]] || fail "Gate B requires an existing Gate A marker"
  [[ "$(read_field "$gate_a_marker" schema_version)" == "1" && "$(read_field "$gate_a_marker" approval_kind)" == "gate-a" ]] || fail "Gate A marker schema is invalid"
  [[ -n "$(read_field "$gate_a_marker" explicit_user_message)" ]] || fail "Gate A marker lacks explicit approval text"
  gate_a_time="$(read_field "$gate_a_marker" approved_at)"
  gate_a_epoch="$(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$gate_a_time" '+%s' 2>/dev/null || true)"
  [[ -n "$gate_a_epoch" && "$gate_a_epoch" -le "$(/bin/date -u '+%s')" ]] || fail "Gate A marker time is invalid"
  gate_a_manifest_hash="$(read_field "$gate_a_marker" manifest_sha256)"
  gate_a_archive="$PROJECT_DIR/dist/candidates/$gate_a_manifest_hash"
  "$SCRIPT_DIR/verify_candidate_archive.sh" "$gate_a_archive" "$gate_a_manifest_hash" >/dev/null
  gate_a_tree="$(read_field "$gate_a_marker" source_tree_hash)"
  [[ "$gate_a_tree" == "$(read_field "$gate_a_archive/candidate-manifest.json" source_tree_hash)" ]] || fail "Gate A marker differs from immutable evidence"
  [[ "$(read_field "$gate_a_marker" app_binary_sha256)" == "$(read_field "$gate_a_archive/candidate-manifest.json" app_binary_sha256)" ]] || fail "Gate A binary differs from immutable evidence"
  [[ "$gate_a_tree" == "$(read_field "$CANDIDATE_MANIFEST" source_tree_hash)" ]] || fail "Final manifest source tree differs from Gate A"
  identity_plist="$(mktemp "${TMPDIR:-/tmp}/ring-stats-gate-b-verify.XXXXXX.plist")"
  trap '/bin/rm -f "$identity_plist"' EXIT
  "$SCRIPT_DIR/verify_final_artifact.sh" "$target" "$APP_PATH" "$identity_plist" >/dev/null
  [[ "$(read_field "$CANDIDATE_MANIFEST" bundle_identity_sha256)" == "$(read_field "$identity_plist" bundle_sha256)" ]] || fail "Final manifest bundle identity differs from artifact"
  [[ "$(read_field "$CANDIDATE_MANIFEST" app_binary_sha256)" == "$(read_field "$identity_plist" artifact_executable_sha256)" ]] || fail "Final manifest executable differs from artifact"
  for metadata_field in bundle_identifier version build; do
    [[ "$(read_field "$CANDIDATE_MANIFEST" "$metadata_field")" == "$(read_field "$identity_plist" "$metadata_field")" ]] || fail "Final manifest metadata differs: $metadata_field"
  done
  for field_name in artifact_sha256 bundle_sha256 artifact_executable_sha256 installed_bundle_sha256 installed_executable_sha256 bundle_identifier version build; do
    [[ "$(read_field "$marker" "$field_name")" == "$(read_field "$identity_plist" "$field_name")" ]] || fail "Gate B field differs: $field_name"
  done
  trap - EXIT
  /bin/rm -f "$identity_plist"
fi

echo "Verified $kind approval: $marker"
