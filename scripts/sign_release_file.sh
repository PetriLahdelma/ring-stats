#!/bin/bash
# Signs a release file with the SSH key Git uses to sign release tags.
#
# Usage: sign_release_file.sh <repo-dir> <file>
#        sign_release_file.sh <repo-dir> --check
#
# Produces <file>.sig, verifiable with verify_release_attestation.sh or
#   ssh-keygen -Y verify -f allowed_signers -I <email> -n ring-stats-release \
#     -s <file>.sig < <file>
# Release signing uses SSH keys only (gpg.format ssh), so one documented
# verification path works for every release. --check validates the
# configuration without signing, so the release script can fail before it
# spends time on notarization.
set -euo pipefail

repo_dir="${1:?repository directory required}"
file="${2:?file or --check required}"

format="$(/usr/bin/git -C "$repo_dir" config --get gpg.format || true)"
key="$(/usr/bin/git -C "$repo_dir" config --get user.signingkey || true)"
[[ "$format" == "ssh" ]] || { echo "Release signing needs gpg.format=ssh (see RELEASING.md)." >&2; exit 1; }
[[ -n "$key" ]] || { echo "Set user.signingkey to the release SSH key (see RELEASING.md)." >&2; exit 1; }

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ring-stats-sign.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
# Git accepts a key file path, "key::<public key>", or a bare public key.
# ssh-keygen needs a file; a public key file signs through ssh-agent.
case "$key" in
  key::*) printf '%s\n' "${key#key::}" > "$work/signing.pub"; key_file="$work/signing.pub" ;;
  ssh-*|ecdsa-*|sk-*) printf '%s\n' "$key" > "$work/signing.pub"; key_file="$work/signing.pub" ;;
  *) key_file="${key/#\~/$HOME}" ;;
esac
[[ -f "$key_file" ]] || { echo "Signing key file not found: $key_file" >&2; exit 1; }

if [[ "$file" == "--check" ]]; then
  printf 'ring-stats signing check' > "$work/check"
  /usr/bin/ssh-keygen -q -Y sign -f "$key_file" -n ring-stats-release "$work/check" \
    || { echo "The release key cannot sign (is it loaded in ssh-agent?)." >&2; exit 1; }
  echo "Release signing key is ready."
  exit 0
fi

[[ -f "$file" ]] || { echo "Missing file: $file" >&2; exit 1; }
/bin/rm -f "$file.sig"
/usr/bin/ssh-keygen -q -Y sign -f "$key_file" -n ring-stats-release "$file"
echo "Signature: $file.sig"
