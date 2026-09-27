#!/bin/bash
# Writes a CycloneDX 1.5 software bill of materials for a built Ring Stats app.
#
# Usage: generate_sbom.sh <app-bundle> <output.cdx.json>
#
# It lists the application with its executable's SHA-256, every Swift package
# dependency (there are none today; the list is generated, not assumed), each
# system framework and library the executable links, and the toolchain.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
app="${1:?app bundle required}"
output="${2:?output path required}"
executable="$app/Contents/MacOS/RingStats"
[[ -x "$executable" ]] || { echo "Missing executable: $executable" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-sbom.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT

/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" > "$work/version"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" > "$work/bundle-id"
/usr/bin/shasum -a 256 "$executable" | /usr/bin/awk '{print $1}' > "$work/sha256"
/usr/bin/swift package --package-path "$PROJECT_DIR" show-dependencies --format json > "$work/dependencies.json"
# Dependency lines are tab-indented; the per-architecture header lines are not
# and contain the build path, so they must be excluded.
/usr/bin/otool -L -arch all "$executable" | /usr/bin/awk '/^\t\// {print $1}' | LC_ALL=C /usr/bin/sort -u > "$work/linked"
/usr/bin/swift --version 2>&1 | /usr/bin/head -1 > "$work/swift"
/usr/bin/xcodebuild -version | /usr/bin/head -1 > "$work/xcode"
/usr/bin/git -C "$PROJECT_DIR" rev-parse HEAD > "$work/commit"

/usr/bin/python3 - "$work" "$output" <<'PY'
import json, pathlib, sys, uuid, datetime
work, output = pathlib.Path(sys.argv[1]), sys.argv[2]
read = lambda name: (work / name).read_text().strip()
version = read("version")
app_ref = f"pkg:swift/ring-stats@{version}"

def swift_dependencies(node):
    for dependency in node.get("dependencies", []):
        yield dependency
        yield from swift_dependencies(dependency)

components = []
for dependency in swift_dependencies(json.loads(read("dependencies.json"))):
    components.append({
        "type": "library",
        "bom-ref": f"pkg:swift/{dependency['identity']}@{dependency.get('version', 'unspecified')}",
        "name": dependency["name"],
        "version": dependency.get("version", "unspecified"),
        "purl": f"pkg:swift/{dependency['identity']}@{dependency.get('version', 'unspecified')}",
        "externalReferences": [{"type": "vcs", "url": dependency.get("url", "")}],
    })
for path in read("linked").splitlines():
    name = pathlib.Path(path).name
    if ".framework/" in path:
        name = path.split(".framework/")[0].rsplit("/", 1)[-1]
    components.append({
        "type": "framework" if ".framework/" in path else "library",
        "bom-ref": f"macos:{path}",
        "name": name,
        "supplier": {"name": "Apple Inc."},
        "scope": "required",
        "properties": [
            {"name": "ringstats:path", "value": path},
            {"name": "ringstats:provided-by", "value": "operating system"},
        ],
    })

bom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": f"urn:uuid:{uuid.uuid4()}",
    "version": 1,
    "metadata": {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tools": {"components": [
            {"type": "application", "name": "swift", "version": read("swift")},
            {"type": "application", "name": "xcode", "version": read("xcode")},
        ]},
        "component": {
            "type": "application",
            "bom-ref": app_ref,
            "name": "Ring Stats",
            "version": version,
            "supplier": {"name": "Digitaltableteur"},
            "licenses": [{"license": {"id": "MIT"}}],
            "hashes": [{"alg": "SHA-256", "content": read("sha256")}],
            "properties": [
                {"name": "ringstats:bundle-identifier", "value": read("bundle-id")},
                {"name": "ringstats:source-commit", "value": read("commit")},
            ],
            "externalReferences": [{"type": "vcs", "url": "https://github.com/PetriLahdelma/ring-stats"}],
        },
    },
    "components": components,
    "dependencies": [{"ref": app_ref, "dependsOn": [c["bom-ref"] for c in components]}],
}
pathlib.Path(output).write_text(json.dumps(bom, indent=2) + "\n")
print(f"SBOM: {output} ({len(components)} components)")
PY
