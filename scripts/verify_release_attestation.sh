#!/bin/bash
# Verifies a signed release attestation and the files it covers.
#
# Usage: verify_release_attestation.sh <attestation.intoto.json> <allowed-signers> <signer-email> <file>...
#
# Checks the SSH signature (<attestation>.sig) against an allowed-signers file
# holding the maintainer's published key, then checks that every given file's
# SHA-256 matches a subject in the attestation.
set -euo pipefail

attestation="${1:?attestation required}"
allowed_signers="${2:?allowed-signers file required}"
signer="${3:?signer identity required}"
shift 3
[[ "$#" -gt 0 ]] || { echo "Name at least one file to verify." >&2; exit 1; }

/usr/bin/ssh-keygen -Y verify -f "$allowed_signers" -I "$signer" -n ring-stats-release \
  -s "$attestation.sig" < "$attestation" >/dev/null \
  || { echo "Attestation signature is not valid for $signer." >&2; exit 1; }

for file in "$@"; do
  name="$(/usr/bin/basename "$file")"
  actual="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
  expected="$(/usr/bin/python3 -c '
import json, sys
statement = json.load(open(sys.argv[1]))
print(next((s["digest"]["sha256"] for s in statement["subject"] if s["name"] == sys.argv[2]), ""))
' "$attestation" "$name")"
  [[ -n "$expected" ]] || { echo "$name is not covered by the attestation." >&2; exit 1; }
  [[ "$actual" == "$expected" ]] || { echo "$name does not match its attested digest." >&2; exit 1; }
  echo "Verified: $name"
done
echo "Attestation verified."
