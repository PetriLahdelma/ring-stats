#!/bin/bash
# The Gate B evidence cross-check, shared by the marker writer and the
# verifier so the two cannot drift: the Gate A marker must be sound and match
# its immutable archive, the final manifest must descend from that Gate A
# tree, and the final artifact's identity must match the manifest.
#
# Expects the caller's globals: SCRIPT_DIR, PROJECT_DIR, APPROVAL_DIR,
# CANDIDATE_MANIFEST, APP_PATH, and fail() and read_field() from common.sh.
# Arguments: the final artifact, and the path of a plist the identity
# verifier may write (the caller creates and removes it).
cross_check_gate_b_evidence() {
  local target="$1" identity_plist="$2"
  local gate_a_marker="$APPROVAL_DIR/gate-a.json"
  [[ -f "$gate_a_marker" && ! -L "$gate_a_marker" ]] || fail "Gate B requires an existing Gate A marker"
  [[ "$(read_field "$gate_a_marker" schema_version)" == "1" && "$(read_field "$gate_a_marker" approval_kind)" == "gate-a" ]] || fail "Gate A marker schema is invalid"
  [[ -n "$(read_field "$gate_a_marker" explicit_user_message)" ]] || fail "Gate A marker lacks explicit approval text"
  local gate_a_time gate_a_epoch
  gate_a_time="$(read_field "$gate_a_marker" approved_at)"
  gate_a_epoch="$(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$gate_a_time" '+%s' 2>/dev/null || true)"
  [[ -n "$gate_a_epoch" && "$gate_a_epoch" -le "$(/bin/date -u '+%s')" ]] || fail "Gate A marker time is invalid"
  local gate_a_manifest_hash gate_a_archive gate_a_tree
  gate_a_manifest_hash="$(read_field "$gate_a_marker" manifest_sha256)"
  gate_a_archive="$PROJECT_DIR/dist/candidates/$gate_a_manifest_hash"
  "$SCRIPT_DIR/verify_candidate_archive.sh" "$gate_a_archive" "$gate_a_manifest_hash" >/dev/null
  gate_a_tree="$(read_field "$gate_a_marker" source_tree_hash)"
  [[ "$gate_a_tree" == "$(read_field "$gate_a_archive/candidate-manifest.json" source_tree_hash)" ]] || fail "Gate A marker differs from immutable evidence"
  [[ "$(read_field "$gate_a_marker" app_binary_sha256)" == "$(read_field "$gate_a_archive/candidate-manifest.json" app_binary_sha256)" ]] || fail "Gate A binary differs from immutable evidence"
  [[ "$gate_a_tree" == "$(read_field "$CANDIDATE_MANIFEST" source_tree_hash)" ]] || fail "Final manifest source tree differs from Gate A"
  "$SCRIPT_DIR/verify_final_artifact.sh" "$target" "$APP_PATH" "$identity_plist" >/dev/null
  [[ "$(read_field "$CANDIDATE_MANIFEST" bundle_identity_sha256)" == "$(read_field "$identity_plist" bundle_sha256)" ]] || fail "Final manifest bundle identity differs from artifact"
  [[ "$(read_field "$CANDIDATE_MANIFEST" app_binary_sha256)" == "$(read_field "$identity_plist" artifact_executable_sha256)" ]] || fail "Final manifest executable differs from artifact"
  local metadata_field
  for metadata_field in bundle_identifier version build; do
    [[ "$(read_field "$CANDIDATE_MANIFEST" "$metadata_field")" == "$(read_field "$identity_plist" "$metadata_field")" ]] || fail "Final manifest metadata differs: $metadata_field"
  done
}

# The identity fields a Gate B marker records from the artifact.
export GATE_B_IDENTITY_FIELDS="artifact_sha256 bundle_sha256 artifact_executable_sha256 installed_bundle_sha256 installed_executable_sha256 bundle_identifier version build"
