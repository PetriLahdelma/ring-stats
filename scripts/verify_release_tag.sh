#!/bin/bash
# Verifies that HEAD of a repository is a releasable tag and prints its name.
#
# Usage: verify_release_tag.sh <repo-dir> <expected-version> <release-branch-ref>
#
# The tag must be an exact v<version> tag on HEAD, annotated, pointing at the
# fetched protected branch commit, and signed by a trusted key. For SSH
# signatures, trust comes from gpg.ssh.allowedSignersFile, which pins the
# release key. For GPG signatures, the key must be at least fully trusted in
# the local keyring (gpg.minTrustLevel=fully), so a valid signature from an
# arbitrary imported key is not enough. ALLOW_UNSIGNED_TAG=1 skips only the
# signature check, for a documented exception.
set -euo pipefail

repo_dir="${1:?repository directory required}"
expected_version="${2:?expected version required}"
branch_ref="${3:?release branch ref required}"

exact_tag="$(/usr/bin/git -C "$repo_dir" describe --exact-match --tags HEAD 2>/dev/null || true)"
if [[ -z "$exact_tag" || "$exact_tag" != v* ]]; then
  echo "Release signing requires HEAD to be an exact v* tag." >&2
  exit 1
fi
if [[ "$(/usr/bin/git -C "$repo_dir" cat-file -t "$exact_tag")" != "tag" ]]; then
  echo "Release tag must be annotated: $exact_tag" >&2
  exit 1
fi
if [[ "${exact_tag#v}" != "$expected_version" ]]; then
  echo "Tag version ${exact_tag#v} does not match bundle version $expected_version." >&2
  exit 1
fi
# A stale or locally rewritten remote-tracking ref must not pass as the
# protected branch: refresh it from the remote first.
if [[ "$branch_ref" == origin/* ]]; then
  /usr/bin/git -C "$repo_dir" fetch --quiet --no-tags origin "+refs/heads/${branch_ref#origin/}:refs/remotes/$branch_ref" \
    || { echo "Could not fetch $branch_ref from origin." >&2; exit 1; }
fi
if ! branch_commit="$(/usr/bin/git -C "$repo_dir" rev-parse --verify "$branch_ref^{commit}" 2>/dev/null)"; then
  echo "Release branch ref is unavailable: $branch_ref" >&2
  echo "Fetch the protected release branch before signing." >&2
  exit 1
fi
tag_commit="$(/usr/bin/git -C "$repo_dir" rev-parse "$exact_tag^{commit}")"
if [[ "$tag_commit" != "$branch_commit" ]]; then
  echo "Release tag $exact_tag must point to the exact $branch_ref commit." >&2
  exit 1
fi
if [[ "${ALLOW_UNSIGNED_TAG:-0}" == "1" ]]; then
  echo "warning: signature verification skipped for $exact_tag (ALLOW_UNSIGNED_TAG=1)." >&2
elif ! /usr/bin/git -C "$repo_dir" -c gpg.minTrustLevel=fully verify-tag "$exact_tag" >/dev/null 2>&1; then
  echo "Release tag $exact_tag has no valid signature from a trusted release key." >&2
  echo "Create it with 'git tag -s' using the pinned release key." >&2
  echo "See RELEASING.md for signing-key setup." >&2
  exit 1
fi
printf '%s\n' "$exact_tag"
