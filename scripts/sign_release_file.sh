#!/bin/bash
# Signs a release file with the same key Git uses to sign release tags.
#
# Usage: sign_release_file.sh <repo-dir> <file>
#
# SSH keys (gpg.format ssh) produce <file>.sig, verifiable with
#   ssh-keygen -Y verify -f allowed_signers -I <email> -n ring-stats-release \
#     -s <file>.sig < <file>
# GPG keys produce an armored <file>.asc, verifiable with gpg --verify.
set -euo pipefail

repo_dir="${1:?repository directory required}"
file="${2:?file required}"
[[ -f "$file" ]] || { echo "Missing file: $file" >&2; exit 1; }

format="$(/usr/bin/git -C "$repo_dir" config --get gpg.format || echo openpgp)"
key="$(/usr/bin/git -C "$repo_dir" config --get user.signingkey || true)"
[[ -n "$key" ]] || { echo "Set user.signingkey to the release signing key (see RELEASING.md)." >&2; exit 1; }

case "$format" in
  ssh)
    /bin/rm -f "$file.sig"
    /usr/bin/ssh-keygen -q -Y sign -f "${key/#\~/$HOME}" -n ring-stats-release "$file"
    echo "Signature: $file.sig"
    ;;
  openpgp)
    /bin/rm -f "$file.asc"
    gpg --batch --yes --local-user "$key" --armor --detach-sign --output "$file.asc" "$file"
    echo "Signature: $file.asc"
    ;;
  *)
    echo "Unsupported gpg.format: $format" >&2
    exit 1
    ;;
esac
