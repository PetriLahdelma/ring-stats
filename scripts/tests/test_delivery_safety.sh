#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
TEST_ROOT_RAW="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-delivery-tests.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT_RAW" && pwd -P)"
trap '/bin/rm -rf "$TEST_ROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
reset_fixture_dirs() {
  [[ "$applications" == "$TEST_ROOT/"* && "$trash" == "$TEST_ROOT/"* ]] || fail "unsafe fixture cleanup paths"
  /bin/rm -rf "$applications" "$trash"
  /bin/mkdir -p "$applications" "$trash"
}
expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

make_app() {
  local path="$1" marker="$2"
  /bin/mkdir -p "$path/Contents/MacOS"
  /usr/bin/plutil -create xml1 "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string com.digitaltableteur.ringstats "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string 1.1.1 "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleVersion -string 3 "$path/Contents/Info.plist"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$marker" > "$path/Contents/MacOS/RingStats"
  /bin/chmod +x "$path/Contents/MacOS/RingStats"
}

make_manifest() {
  local path="$1" tree_hash="$2"
  /usr/bin/plutil -create xml1 "$path"
  /usr/bin/plutil -insert source_tree_hash -string "$tree_hash" "$path"
  /usr/bin/plutil -insert app_binary_sha256 -string "$(/usr/bin/shasum -a 256 "$candidate/Contents/MacOS/RingStats" | /usr/bin/awk '{print $1}')" "$path"
  /usr/bin/plutil -insert candidate_path -string "$TEST_ROOT/candidate/Ring Stats.app" "$path"
}

refresh_manifest_checksum() {
  local path="$1"
  /usr/bin/shasum -a 256 "$path" > "${path%.*}.sha256"
}

candidate="$TEST_ROOT/candidate/Ring Stats.app"
applications="$TEST_ROOT/Applications"
trash="$TEST_ROOT/Trash"
approvals="$TEST_ROOT/approvals"
/bin/mkdir -p "$(dirname "$candidate")" "$applications" "$trash" "$approvals"
make_app "$candidate" candidate
running_check="$TEST_ROOT/not-running"
printf '#!/bin/sh\nprintf "false\\n"\n' > "$running_check"
/bin/chmod +x "$running_check"
launched_check="$TEST_ROOT/running"
printf '#!/bin/sh\nprintf "true\\n"\n' > "$launched_check"
/bin/chmod +x "$launched_check"

common_install_env=(
  RING_STATS_TEST_MODE=1
  RING_STATS_TEST_ROOT="$TEST_ROOT"
  USER_APPLICATIONS_DIR="$applications"
  TRASH_DIR="$trash"
  OSASCRIPT_BIN=/usr/bin/true
  QUIT_RUNNING_CHECK_BIN="$running_check"
  LAUNCH_RUNNING_CHECK_BIN="$launched_check"
  CODESIGN_BIN=/usr/bin/true
  LSREGISTER_BIN=/usr/bin/true
  MDIMPORT_BIN=/usr/bin/true
  OPEN_BIN=/usr/bin/true
)

for failure_point in stage before_backup after_backup after_copy after_register after_open; do
  reset_fixture_dirs
  make_app "$applications/Ring Stats.app" previous
  expect_failure /usr/bin/env "${common_install_env[@]}" \
    RING_STATS_INSTALL_FAIL_AT="$failure_point" \
    "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate"
  [[ -x "$applications/Ring Stats.app/Contents/MacOS/RingStats" ]] || fail "$failure_point did not restore prior app"
  [[ "$("$applications/Ring Stats.app/Contents/MacOS/RingStats")" == previous ]] || fail "$failure_point restored wrong app"
done

# Refuse to replace while the exact bundle identifier still reports running.
reset_fixture_dirs
make_app "$applications/Ring Stats.app" previous
expect_failure /usr/bin/env "${common_install_env[@]}" QUIT_RUNNING_CHECK_BIN="$launched_check" \
  "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate"
[[ "$("$applications/Ring Stats.app/Contents/MacOS/RingStats")" == previous ]] || fail "quit failure changed prior app"

# Open and launch failures both roll back by moves.
expect_failure /usr/bin/env "${common_install_env[@]}" OPEN_BIN=/usr/bin/false \
  "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate"
[[ "$("$applications/Ring Stats.app/Contents/MacOS/RingStats")" == previous ]] || fail "open failure did not restore prior app"
expect_failure /usr/bin/env "${common_install_env[@]}" LAUNCH_RUNNING_CHECK_BIN="$running_check" \
  "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate"
[[ "$("$applications/Ring Stats.app/Contents/MacOS/RingStats")" == previous ]] || fail "launch failure did not restore prior app"

reset_fixture_dirs
make_app "$applications/Ring Stats.app" previous
install_output="$(/usr/bin/env "${common_install_env[@]}" "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate")"
[[ "$("$applications/Ring Stats.app/Contents/MacOS/RingStats")" == candidate ]] || fail "successful install did not install candidate"
recovery_path="$(printf '%s\n' "$install_output" | /usr/bin/sed -n 's/^Previous version recovery path: //p')"
[[ -x "$recovery_path/Contents/MacOS/RingStats" ]] || fail "successful install did not preserve recovery app"
[[ "$("$recovery_path/Contents/MacOS/RingStats")" == previous ]] || fail "recovery path contains wrong app"

# A first install has no prior backup, and a repeated install preserves the first candidate.
reset_fixture_dirs
first_output="$(/usr/bin/env "${common_install_env[@]}" "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate")"
[[ "$first_output" == *"recovery path: none"* ]] || fail "first install reported an unexpected backup"
second_output="$(/usr/bin/env "${common_install_env[@]}" "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate")"
second_recovery="$(printf '%s\n' "$second_output" | /usr/bin/sed -n 's/^Previous version recovery path: //p')"
[[ -x "$second_recovery/Contents/MacOS/RingStats" ]] || fail "repeated install did not preserve prior candidate"

# Dangerous roots and linked candidates are rejected.
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 RING_STATS_TEST_ROOT="$TEST_ROOT" USER_APPLICATIONS_DIR=/ TRASH_DIR="$trash" "$PROJECT_DIR/scripts/install_local_candidate.sh" "$candidate"
linked_candidate="$TEST_ROOT/linked.app"
/bin/ln -s "$candidate" "$linked_candidate"
expect_failure /usr/bin/env "${common_install_env[@]}" "$PROJECT_DIR/scripts/install_local_candidate.sh" "$linked_candidate"

manifest="$TEST_ROOT/candidate-manifest.plist"
make_manifest "$manifest" tree-one
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 APPROVAL_DIR="$approvals" "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-a "$manifest"
/usr/bin/env RING_STATS_TEST_MODE=1 APPROVAL_DIR="$approvals" "$PROJECT_DIR/scripts/write_approval_marker.sh" gate-a "$manifest" "Fixture approval for tree one" >/dev/null
/usr/bin/env RING_STATS_TEST_MODE=1 APPROVAL_DIR="$approvals" "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-a "$manifest" >/dev/null
make_manifest "$manifest" tree-two
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 APPROVAL_DIR="$approvals" "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-a "$manifest"

# Gate A survives a new commit with the same tree and fails after tree content changes.
gate_repo="$TEST_ROOT/gate-repo"
/bin/mkdir -p "$gate_repo"
/usr/bin/git -C "$gate_repo" init -q
/usr/bin/git -C "$gate_repo" config user.email fixture@example.invalid
/usr/bin/git -C "$gate_repo" config user.name Fixture
printf 'same tree\n' > "$gate_repo/tracked.txt"
/usr/bin/git -C "$gate_repo" add tracked.txt
/usr/bin/git -C "$gate_repo" commit -qm initial
gate_tree="$(/usr/bin/git -C "$gate_repo" write-tree)"
make_manifest "$manifest" "$gate_tree"
/usr/bin/env RING_STATS_TEST_MODE=1 TEST_PROJECT_DIR="$gate_repo" APPROVAL_DIR="$approvals" \
  "$PROJECT_DIR/scripts/write_approval_marker.sh" gate-a "$manifest" "Fixture same-tree approval" >/dev/null
/usr/bin/git -C "$gate_repo" commit --allow-empty -qm same-tree-new-commit
/usr/bin/env RING_STATS_TEST_MODE=1 TEST_PROJECT_DIR="$gate_repo" APPROVAL_DIR="$approvals" \
  "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-a "$manifest" >/dev/null
printf 'changed tree\n' > "$gate_repo/tracked.txt"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 TEST_PROJECT_DIR="$gate_repo" APPROVAL_DIR="$approvals" \
  "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-a "$manifest"

artifact="$TEST_ROOT/final.dmg"
printf 'final-artifact-one' > "$artifact"
artifact_app="$TEST_ROOT/artifact/Ring Stats.app"
/bin/mkdir -p "$(dirname "$artifact_app")"
/usr/bin/ditto "$PROJECT_DIR/dist/Ring Stats.app" "$artifact_app"
[[ "$applications" == "$TEST_ROOT/"* ]] || fail "unsafe fixture cleanup path"
/bin/rm -rf "$applications"
/bin/mkdir -p "$applications"
/usr/bin/ditto "$PROJECT_DIR/dist/Ring Stats.app" "$applications/Ring Stats.app"
final_manifest="$PROJECT_DIR/dist/candidate-manifest.json"
/usr/bin/env RING_STATS_TEST_MODE=1 APPROVAL_DIR="$approvals" \
  "$PROJECT_DIR/scripts/write_approval_marker.sh" gate-a "$final_manifest" "Fixture Gate A for final tree" >/dev/null
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true APPROVAL_DIR="$approvals" APP_PATH="$applications/Ring Stats.app" ARTIFACT_APP_PATH="$artifact_app" CANDIDATE_MANIFEST="$final_manifest" \
  "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-b "$artifact"
/usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true APPROVAL_DIR="$approvals" APP_PATH="$applications/Ring Stats.app" ARTIFACT_APP_PATH="$artifact_app" CANDIDATE_MANIFEST="$final_manifest" \
  "$PROJECT_DIR/scripts/write_approval_marker.sh" gate-b "$artifact" "Fixture approval for exact final artifact" >/dev/null
/usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true APPROVAL_DIR="$approvals" APP_PATH="$applications/Ring Stats.app" ARTIFACT_APP_PATH="$artifact_app" CANDIDATE_MANIFEST="$final_manifest" \
  "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-b "$artifact" >/dev/null
printf 'final-artifact-two' > "$artifact"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true APPROVAL_DIR="$approvals" APP_PATH="$applications/Ring Stats.app" ARTIFACT_APP_PATH="$artifact_app" CANDIDATE_MANIFEST="$final_manifest" \
  "$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-b "$artifact"

# Gate B refuses mix-and-match final manifests even when the artifact is otherwise valid.
mixed_manifest="$TEST_ROOT/mixed-manifest.json"
/bin/cp "$final_manifest" "$mixed_manifest"
/usr/bin/plutil -replace source_tree_hash -string 0000000000000000000000000000000000000000 "$mixed_manifest"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true APPROVAL_DIR="$approvals" APP_PATH="$applications/Ring Stats.app" ARTIFACT_APP_PATH="$artifact_app" CANDIDATE_MANIFEST="$mixed_manifest" \
  "$PROJECT_DIR/scripts/write_approval_marker.sh" gate-b "$artifact" "Fixture mixed tree"
/bin/cp "$final_manifest" "$mixed_manifest"
/usr/bin/plutil -replace app_binary_sha256 -string 0000000000000000000000000000000000000000000000000000000000000000 "$mixed_manifest"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true APPROVAL_DIR="$approvals" APP_PATH="$applications/Ring Stats.app" ARTIFACT_APP_PATH="$artifact_app" CANDIDATE_MANIFEST="$mixed_manifest" \
  "$PROJECT_DIR/scripts/write_approval_marker.sh" gate-b "$artifact" "Fixture mixed binary"

# Full-bundle identity rejects resource and Info.plist divergence even when the executable matches.
/bin/mkdir -p "$applications/Ring Stats.app/Contents/Resources" "$artifact_app/Contents/Resources"
printf 'mounted resource' > "$artifact_app/Contents/Resources/state.txt"
printf 'installed mismatch' > "$applications/Ring Stats.app/Contents/Resources/state.txt"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true ARTIFACT_APP_PATH="$artifact_app" \
  "$PROJECT_DIR/scripts/verify_final_artifact.sh" "$artifact" "$applications/Ring Stats.app" "$TEST_ROOT/resource-mismatch.plist"
/bin/cp "$artifact_app/Contents/Resources/state.txt" "$applications/Ring Stats.app/Contents/Resources/state.txt"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier invalid.bundle' "$applications/Ring Stats.app/Contents/Info.plist"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 CODESIGN_BIN=/usr/bin/true ARTIFACT_APP_PATH="$artifact_app" \
  "$PROJECT_DIR/scripts/verify_final_artifact.sh" "$artifact" "$applications/Ring Stats.app" "$TEST_ROOT/info-mismatch.plist"

# Production wrappers reject all test-mode entry.
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 "$PROJECT_DIR/scripts/preflight_remote_collaboration.sh"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 "$PROJECT_DIR/scripts/preflight_publication.sh" "$artifact"
expect_failure /usr/bin/env RING_STATS_TEST_MODE=1 "$PROJECT_DIR/scripts/sign_and_notarize.sh"

# The independent manifest verifier rejects checksum and semantic tampering.
if [[ -f "$PROJECT_DIR/dist/candidate-manifest.json" ]]; then
  manifest_copy="$TEST_ROOT/manifest-copy.json"
  /bin/cp "$PROJECT_DIR/dist/candidate-manifest.json" "$manifest_copy"
  refresh_manifest_checksum "$manifest_copy"
  MANIFEST_HASH_PATH="${manifest_copy%.*}.sha256" RING_STATS_TEST_MODE=1 \
    "$PROJECT_DIR/scripts/verify_candidate_manifest.sh" "$manifest_copy" \
    "$PROJECT_DIR/dist/Ring Stats.app" "$PROJECT_DIR/dist/Ring Stats.app.dSYM" >/dev/null
  /usr/bin/plutil -replace schema_version -integer 99 "$manifest_copy"
  refresh_manifest_checksum "$manifest_copy"
  expect_failure /usr/bin/env MANIFEST_HASH_PATH="${manifest_copy%.*}.sha256" RING_STATS_TEST_MODE=1 \
    "$PROJECT_DIR/scripts/verify_candidate_manifest.sh" "$manifest_copy" "$PROJECT_DIR/dist/Ring Stats.app" "$PROJECT_DIR/dist/Ring Stats.app.dSYM"
  /bin/cp "$PROJECT_DIR/dist/candidate-manifest.json" "$manifest_copy"
  /usr/bin/plutil -replace executable_uuids -string arm64:BAD "$manifest_copy"
  refresh_manifest_checksum "$manifest_copy"
  expect_failure /usr/bin/env MANIFEST_HASH_PATH="${manifest_copy%.*}.sha256" RING_STATS_TEST_MODE=1 \
    "$PROJECT_DIR/scripts/verify_candidate_manifest.sh" "$manifest_copy" "$PROJECT_DIR/dist/Ring Stats.app" "$PROJECT_DIR/dist/Ring Stats.app.dSYM"
  /bin/cp "$PROJECT_DIR/dist/candidate-manifest.json" "$manifest_copy"
  printf 'tamper' >> "$manifest_copy"
  expect_failure /usr/bin/env MANIFEST_HASH_PATH="${manifest_copy%.*}.sha256" RING_STATS_TEST_MODE=1 \
    "$PROJECT_DIR/scripts/verify_candidate_manifest.sh" "$manifest_copy" "$PROJECT_DIR/dist/Ring Stats.app" "$PROJECT_DIR/dist/Ring Stats.app.dSYM"

  # Build-time dirty metadata remains truthful after a same-tree commit makes
  # the checkout clean; tree changes still invalidate the manifest.
  manifest_repo="$TEST_ROOT/manifest-repo"
  /bin/mkdir -p "$manifest_repo"
  /usr/bin/git -C "$manifest_repo" init -q
  /usr/bin/git -C "$manifest_repo" config user.email fixture@example.invalid
  /usr/bin/git -C "$manifest_repo" config user.name Fixture
  printf 'base\n' > "$manifest_repo/tracked.txt"
  /usr/bin/git -C "$manifest_repo" add tracked.txt
  /usr/bin/git -C "$manifest_repo" commit -qm base
  manifest_base_commit="$(/usr/bin/git -C "$manifest_repo" rev-parse HEAD)"
  printf 'approved tree\n' > "$manifest_repo/tracked.txt"
  /usr/bin/git -C "$manifest_repo" add tracked.txt
  manifest_approved_tree="$(/usr/bin/git -C "$manifest_repo" write-tree)"
  /bin/cp "$PROJECT_DIR/dist/candidate-manifest.json" "$manifest_copy"
  /usr/bin/plutil -replace source_commit -string "$manifest_base_commit" "$manifest_copy"
  /usr/bin/plutil -replace source_tree_hash -string "$manifest_approved_tree" "$manifest_copy"
  /usr/bin/plutil -replace source_worktree_clean -bool false "$manifest_copy"
  refresh_manifest_checksum "$manifest_copy"
  /usr/bin/git -C "$manifest_repo" commit -qm approved-tree
  /usr/bin/env MANIFEST_HASH_PATH="${manifest_copy%.*}.sha256" RING_STATS_TEST_MODE=1 TEST_PROJECT_DIR="$manifest_repo" \
    "$PROJECT_DIR/scripts/verify_candidate_manifest.sh" "$manifest_copy" "$PROJECT_DIR/dist/Ring Stats.app" "$PROJECT_DIR/dist/Ring Stats.app.dSYM" >/dev/null
  printf 'different tree\n' > "$manifest_repo/tracked.txt"
  expect_failure /usr/bin/env MANIFEST_HASH_PATH="${manifest_copy%.*}.sha256" RING_STATS_TEST_MODE=1 TEST_PROJECT_DIR="$manifest_repo" \
    "$PROJECT_DIR/scripts/verify_candidate_manifest.sh" "$manifest_copy" "$PROJECT_DIR/dist/Ring Stats.app" "$PROJECT_DIR/dist/Ring Stats.app.dSYM"

  # Content-addressed archives are complete, tamper-evident, and immutable on repeated emission.
  current_manifest_hash="$(/usr/bin/shasum -a 256 "$PROJECT_DIR/dist/candidate-manifest.json" | /usr/bin/awk '{print $1}')"
  "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$PROJECT_DIR/dist/candidates/$current_manifest_hash" "$current_manifest_hash" >/dev/null
  archive_copy="$TEST_ROOT/archive-copy"
  /usr/bin/ditto "$PROJECT_DIR/dist/candidates/$current_manifest_hash" "$archive_copy"
  printf 'tamper' >> "$archive_copy/uuids.txt"
  expect_failure "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$archive_copy" "$current_manifest_hash"
  /bin/rm -rf "$archive_copy"
  /usr/bin/ditto "$PROJECT_DIR/dist/candidates/$current_manifest_hash" "$archive_copy"
  /bin/mkdir "$archive_copy/unexpected-directory"
  expect_failure "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$archive_copy" "$current_manifest_hash"
  /bin/rm -rf "$archive_copy"
  /usr/bin/ditto "$PROJECT_DIR/dist/candidates/$current_manifest_hash" "$archive_copy"
  hostile_extract="$TEST_ROOT/hostile-dsym"
  /bin/mkdir -p "$hostile_extract"
  /usr/bin/ditto -x -k "$archive_copy/Ring-Stats.dSYM.zip" "$hostile_extract"
  printf 'dSYM byte tamper' >> "$hostile_extract/Ring Stats.app.dSYM/Contents/Info.plist"
  /bin/rm -f "$archive_copy/Ring-Stats.dSYM.zip"
  /usr/bin/ditto -c -k --keepParent "$hostile_extract/Ring Stats.app.dSYM" "$archive_copy/Ring-Stats.dSYM.zip"
  (cd "$archive_copy" && /usr/bin/shasum -a 256 Ring-Stats.dSYM.zip > Ring-Stats.dSYM.zip.sha256)
  expect_failure "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$archive_copy" "$current_manifest_hash"
  /bin/rm -rf "$archive_copy" "$hostile_extract"
  /usr/bin/ditto "$PROJECT_DIR/dist/candidates/$current_manifest_hash" "$archive_copy"
  /bin/mkdir -p "$hostile_extract"
  /usr/bin/ditto -x -k "$archive_copy/Ring-Stats.dSYM.zip" "$hostile_extract"
  /bin/ln -s /tmp "$hostile_extract/Ring Stats.app.dSYM/escape-link"
  /bin/rm -f "$archive_copy/Ring-Stats.dSYM.zip"
  /usr/bin/ditto -c -k --keepParent "$hostile_extract/Ring Stats.app.dSYM" "$archive_copy/Ring-Stats.dSYM.zip"
  (cd "$archive_copy" && /usr/bin/shasum -a 256 Ring-Stats.dSYM.zip > Ring-Stats.dSYM.zip.sha256)
  expect_failure "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$archive_copy" "$current_manifest_hash"
  /bin/rm -rf "$archive_copy" "$hostile_extract"
  /bin/mkdir -p "$archive_copy"
  /bin/cp "$PROJECT_DIR/dist/candidates/$current_manifest_hash/candidate-manifest.json" "$archive_copy/"
  expect_failure "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$archive_copy" "$current_manifest_hash"

  repeat_manifest="$TEST_ROOT/repeat-manifest.json"
  repeat_checksum="$TEST_ROOT/repeat-manifest.sha256"
  VERIFIED_AT=2026-09-27T12:00:00Z RING_STATS_TEST_MODE=1 MANIFEST_PATH="$repeat_manifest" MANIFEST_HASH_PATH="$repeat_checksum" \
    "$PROJECT_DIR/scripts/emit_candidate_manifest.sh" >/dev/null
  repeat_hash="$(/usr/bin/awk '{print $1}' "$repeat_checksum")"
  before_inventory="$(/usr/bin/find "$PROJECT_DIR/dist/candidates/$repeat_hash" -type f -exec /usr/bin/shasum -a 256 {} \; | LC_ALL=C /usr/bin/sort)"
  VERIFIED_AT=2026-09-27T12:00:00Z RING_STATS_TEST_MODE=1 MANIFEST_PATH="$repeat_manifest" MANIFEST_HASH_PATH="$repeat_checksum" \
    "$PROJECT_DIR/scripts/emit_candidate_manifest.sh" >/dev/null
  after_inventory="$(/usr/bin/find "$PROJECT_DIR/dist/candidates/$repeat_hash" -type f -exec /usr/bin/shasum -a 256 {} \; | LC_ALL=C /usr/bin/sort)"
  [[ "$before_inventory" == "$after_inventory" ]] || fail "repeated candidate emission mutated immutable archive"

  concurrent_one="$TEST_ROOT/concurrent-one.json"
  concurrent_two="$TEST_ROOT/concurrent-two.json"
  VERIFIED_AT=2026-09-27T12:00:01Z RING_STATS_TEST_MODE=1 MANIFEST_PATH="$concurrent_one" MANIFEST_HASH_PATH="$TEST_ROOT/concurrent-one.sha256" \
    "$PROJECT_DIR/scripts/emit_candidate_manifest.sh" >/dev/null & first_emitter=$!
  VERIFIED_AT=2026-09-27T12:00:01Z RING_STATS_TEST_MODE=1 MANIFEST_PATH="$concurrent_two" MANIFEST_HASH_PATH="$TEST_ROOT/concurrent-two.sha256" \
    "$PROJECT_DIR/scripts/emit_candidate_manifest.sh" >/dev/null & second_emitter=$!
  wait "$first_emitter"
  wait "$second_emitter"
  concurrent_hash="$(/usr/bin/awk '{print $1}' "$TEST_ROOT/concurrent-one.sha256")"
  [[ "$concurrent_hash" == "$(/usr/bin/awk '{print $1}' "$TEST_ROOT/concurrent-two.sha256")" ]] || fail "concurrent emitters disagreed on manifest hash"
  "$PROJECT_DIR/scripts/verify_candidate_archive.sh" "$PROJECT_DIR/dist/candidates/$concurrent_hash" "$concurrent_hash" >/dev/null
  [[ -z "$(/usr/bin/find "$PROJECT_DIR/dist/candidates" -maxdepth 1 \( -name ".candidate-$concurrent_hash.*" -o -name ".archive-$concurrent_hash.lock" \) -print -quit)" ]] || fail "concurrent emitters left staging or lock entries"
fi

# Release tags must be exact, annotated, on the release branch, and signed.
tag_repo="$TEST_ROOT/tag-repo"
/bin/mkdir -p "$tag_repo"
/usr/bin/git -C "$tag_repo" init -q -b main
/usr/bin/git -C "$tag_repo" config user.name "Release Test"
/usr/bin/git -C "$tag_repo" config user.email "release-test@example.invalid"
/usr/bin/git -C "$tag_repo" config commit.gpgsign false
/usr/bin/git -C "$tag_repo" config tag.gpgsign false
/usr/bin/git -C "$tag_repo" commit -q --allow-empty -m "release candidate"
verify_tag() { "$PROJECT_DIR/scripts/verify_release_tag.sh" "$tag_repo" 9.9 main; }

/usr/bin/git -C "$tag_repo" tag v9.9
expect_failure verify_tag
/usr/bin/git -C "$tag_repo" tag -d v9.9 >/dev/null
/usr/bin/git -C "$tag_repo" tag -a v9.9 -m "unsigned"
expect_failure verify_tag
[[ "$(ALLOW_UNSIGNED_TAG=1 verify_tag 2>/dev/null)" == "v9.9" ]] || fail "documented unsigned override was rejected"
/usr/bin/git -C "$tag_repo" tag -d v9.9 >/dev/null

/usr/bin/ssh-keygen -q -t ed25519 -N "" -C release-test -f "$TEST_ROOT/release-key"
printf 'release-test@example.invalid %s\n' "$(/bin/cat "$TEST_ROOT/release-key.pub")" > "$TEST_ROOT/allowed-signers"
/usr/bin/git -C "$tag_repo" config gpg.format ssh
/usr/bin/git -C "$tag_repo" config user.signingkey "$TEST_ROOT/release-key"
/usr/bin/git -C "$tag_repo" config gpg.ssh.allowedSignersFile "$TEST_ROOT/allowed-signers"
/usr/bin/git -C "$tag_repo" tag -s v9.9 -m "signed"
[[ "$(verify_tag)" == "v9.9" ]] || fail "a valid signed tag was rejected"
expect_failure "$PROJECT_DIR/scripts/verify_release_tag.sh" "$tag_repo" 9.8 main
/usr/bin/git -C "$tag_repo" commit -q --allow-empty -m "later commit"
/usr/bin/git -C "$tag_repo" checkout -q v9.9
expect_failure verify_tag

# The SBOM describes the built executable and is valid CycloneDX JSON.
if [[ -x "$PROJECT_DIR/dist/Ring Stats.app/Contents/MacOS/RingStats" ]]; then
  "$PROJECT_DIR/scripts/generate_sbom.sh" "$PROJECT_DIR/dist/Ring Stats.app" "$TEST_ROOT/sbom.json" >/dev/null
  /usr/bin/python3 - "$TEST_ROOT/sbom.json" "$(/usr/bin/shasum -a 256 "$PROJECT_DIR/dist/Ring Stats.app/Contents/MacOS/RingStats" | /usr/bin/awk '{print $1}')" <<'PY' || fail "SBOM content is wrong"
import json, sys
bom = json.load(open(sys.argv[1]))
assert bom["bomFormat"] == "CycloneDX" and bom["specVersion"] == "1.5"
app = bom["metadata"]["component"]
assert app["name"] == "Ring Stats"
assert app["hashes"][0]["content"] == sys.argv[2]
names = {component["name"] for component in bom["components"]}
assert {"Foundation", "SwiftUI", "AppKit", "Security", "CFNetwork"} <= names, names
assert all(c.get("supplier", {}).get("name") == "Apple Inc." for c in bom["components"]), "unexpected third-party component"
paths = [p["value"] for c in bom["components"] for p in c.get("properties", []) if p["name"] == "ringstats:path"]
assert paths and all(p.startswith(("/System/", "/usr/lib/")) for p in paths), paths
PY
fi

# The signing preflight passes with an SSH key and fails without SSH format.
"$PROJECT_DIR/scripts/sign_release_file.sh" "$tag_repo" --check >/dev/null || fail "a usable SSH key failed the preflight"
/usr/bin/git -C "$tag_repo" config gpg.format openpgp
expect_failure "$PROJECT_DIR/scripts/sign_release_file.sh" "$tag_repo" --check
/usr/bin/git -C "$tag_repo" config gpg.format ssh

# Release attestations are signed with the tag key and bind exact file digests.
attest_files="$TEST_ROOT/attest"
/bin/mkdir -p "$attest_files"
printf 'disk image' > "$attest_files/Ring-Stats-9.9.dmg"
printf '{}' > "$attest_files/Ring-Stats-9.9.cdx.json"
"$PROJECT_DIR/scripts/create_release_attestation.sh" "$tag_repo" v9.9 "$attest_files/Ring-Stats-9.9.intoto.json" \
  "$attest_files/Ring-Stats-9.9.dmg" "$attest_files/Ring-Stats-9.9.cdx.json" >/dev/null
"$PROJECT_DIR/scripts/sign_release_file.sh" "$tag_repo" "$attest_files/Ring-Stats-9.9.intoto.json" >/dev/null
"$PROJECT_DIR/scripts/verify_release_attestation.sh" "$attest_files/Ring-Stats-9.9.intoto.json" \
  "$TEST_ROOT/allowed-signers" release-test@example.invalid \
  "$attest_files/Ring-Stats-9.9.dmg" "$attest_files/Ring-Stats-9.9.cdx.json" >/dev/null \
  || fail "a valid attestation was rejected"
printf 'tampered' > "$attest_files/Ring-Stats-9.9.dmg"
expect_failure "$PROJECT_DIR/scripts/verify_release_attestation.sh" "$attest_files/Ring-Stats-9.9.intoto.json" \
  "$TEST_ROOT/allowed-signers" release-test@example.invalid "$attest_files/Ring-Stats-9.9.dmg"
printf 'disk image' > "$attest_files/Ring-Stats-9.9.dmg"
expect_failure "$PROJECT_DIR/scripts/verify_release_attestation.sh" "$attest_files/Ring-Stats-9.9.intoto.json" \
  "$TEST_ROOT/allowed-signers" someone-else@example.invalid "$attest_files/Ring-Stats-9.9.dmg"
/usr/bin/python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["subject"][0]["digest"]["sha256"]="0"*64; json.dump(d,open(p,"w"))' \
  "$attest_files/Ring-Stats-9.9.intoto.json"
expect_failure "$PROJECT_DIR/scripts/verify_release_attestation.sh" "$attest_files/Ring-Stats-9.9.intoto.json" \
  "$TEST_ROOT/allowed-signers" release-test@example.invalid "$attest_files/Ring-Stats-9.9.dmg"

echo "Delivery safety tests passed"
