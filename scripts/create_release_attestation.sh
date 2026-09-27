#!/bin/bash
# Writes an in-toto Statement (v1) with a SLSA provenance (v1) predicate that
# binds published release files to the signed tag and commit they came from.
#
# Usage: create_release_attestation.sh <repo-dir> <tag> <output.intoto.json> <file>...
#
# Each file becomes a subject with its SHA-256. The build ran on the
# maintainer's Mac, which the predicate states plainly; the statement is signed
# separately with the maintainer's release key (sign_release_file.sh).
set -euo pipefail

repo_dir="${1:?repository directory required}"
tag="${2:?tag required}"
output="${3:?output path required}"
shift 3
[[ "$#" -gt 0 ]] || { echo "At least one subject file is required." >&2; exit 1; }

commit="$(/usr/bin/git -C "$repo_dir" rev-parse "$tag^{commit}")"
subjects="$(for file in "$@"; do
  [[ -f "$file" ]] || { echo "Missing subject: $file" >&2; exit 1; }
  printf '%s\t%s\n' "$(/usr/bin/basename "$file")" "$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
done)"
toolchain="$(/usr/bin/swift --version 2>&1 | /usr/bin/head -1)"
xcode="$(/usr/bin/xcodebuild -version 2>/dev/null | /usr/bin/head -1 || echo unknown)"

SUBJECTS="$subjects" TAG="$tag" COMMIT="$commit" TOOLCHAIN="$toolchain" XCODE="$xcode" \
/usr/bin/python3 - "$output" <<'PY'
import datetime, json, os, sys
subjects = [
    {"name": name, "digest": {"sha256": digest}}
    for name, digest in (line.split("\t") for line in os.environ["SUBJECTS"].splitlines() if line)
]
repository = "https://github.com/PetriLahdelma/ring-stats"
statement = {
    "_type": "https://in-toto.io/Statement/v1",
    "subject": subjects,
    "predicateType": "https://slsa.dev/provenance/v1",
    "predicate": {
        "buildDefinition": {
            "buildType": f"{repository}/blob/main/RELEASING.md",
            "externalParameters": {
                "source": f"git+{repository}@refs/tags/{os.environ['TAG']}",
                "tag": os.environ["TAG"],
            },
            "internalParameters": {
                "toolchain": os.environ["TOOLCHAIN"],
                "xcode": os.environ["XCODE"],
            },
            "resolvedDependencies": [{
                "uri": f"git+{repository}@refs/tags/{os.environ['TAG']}",
                "digest": {"gitCommit": os.environ["COMMIT"]},
            }],
        },
        "runDetails": {
            "builder": {"id": f"{repository}/blob/main/RELEASING.md#maintainer-mac"},
            "metadata": {
                "finishedOn": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            },
        },
    },
}
with open(sys.argv[1], "w") as handle:
    json.dump(statement, handle, indent=2)
    handle.write("\n")
PY
echo "Attestation: $output"
