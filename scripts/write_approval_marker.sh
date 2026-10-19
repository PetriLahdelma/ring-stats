#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib/common.sh"
source "$(cd "$(dirname "$0")" && pwd -P)/lib/gate_b_evidence.sh"

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
    identity_plist="$(mktemp "${TMPDIR:-/tmp}/ring-stats-gate-b.XXXXXX.plist")"
    trap 'cleanup; /bin/rm -f "$identity_plist"' EXIT
    cross_check_gate_b_evidence "$target" "$identity_plist"
    for field_name in $GATE_B_IDENTITY_FIELDS; do
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
