#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib/common.sh"

archive="${1:-}"
expected_hash="${2:-$(basename "$archive")}" 
[[ -d "$archive" && ! -L "$archive" && "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid candidate archive"
expected_entries="Ring-Stats.dSYM.zip
Ring-Stats.dSYM.zip.sha256
bundle-identity.txt
candidate-manifest.json
candidate-manifest.sha256
dsym-identity.txt
uuids.txt"
actual_entries="$(/usr/bin/find "$archive" -mindepth 1 -maxdepth 1 -print | /usr/bin/sed 's#.*/##' | LC_ALL=C /usr/bin/sort)"
[[ "$actual_entries" == "$expected_entries" ]] || fail "Candidate archive contains unexpected, nested, or partial content"
for name in candidate-manifest.json candidate-manifest.sha256 uuids.txt bundle-identity.txt dsym-identity.txt Ring-Stats.dSYM.zip Ring-Stats.dSYM.zip.sha256; do
  [[ -f "$archive/$name" && ! -L "$archive/$name" ]] || fail "Incomplete candidate archive: $name"
done
(cd "$archive" && /usr/bin/shasum -a 256 -c candidate-manifest.sha256 >/dev/null)
[[ "$(/usr/bin/shasum -a 256 "$archive/candidate-manifest.json" | /usr/bin/awk '{print $1}')" == "$expected_hash" ]] || fail "Archive address differs from manifest"
(cd "$archive" && /usr/bin/shasum -a 256 -c Ring-Stats.dSYM.zip.sha256 >/dev/null)
/usr/bin/unzip -tq "$archive/Ring-Stats.dSYM.zip" >/dev/null
zip_entries="$(/usr/bin/unzip -Z1 "$archive/Ring-Stats.dSYM.zip")"
[[ -n "$zip_entries" ]] || fail "dSYM ZIP is empty"
while IFS= read -r entry; do
  [[ -n "$entry" && "$entry" != /* && "$entry" != *\\* && ! "$entry" =~ (^|/)\.\.(/|$) && ! "$entry" =~ [[:cntrl:]] ]] || fail "Unsafe dSYM ZIP entry: $entry"
  [[ "$entry" == "Ring Stats.app.dSYM" || "$entry" == "Ring Stats.app.dSYM/"* ]] || fail "Unexpected dSYM ZIP root: $entry"
done <<< "$zip_entries"
[[ -z "$(printf '%s\n' "$zip_entries" | LC_ALL=C /usr/bin/sort | /usr/bin/uniq -d)" ]] || fail "Duplicate dSYM ZIP entries"
[[ "$(/usr/bin/plutil -extract executable_uuids raw "$archive/candidate-manifest.json")" == "$(/bin/cat "$archive/uuids.txt")" ]] || fail "Archive UUID inventory differs"
[[ "$(/usr/bin/plutil -extract bundle_identity_sha256 raw "$archive/candidate-manifest.json")" == "$(/usr/bin/shasum -a 256 "$archive/bundle-identity.txt" | /usr/bin/awk '{print $1}')" ]] || fail "Archive bundle identity differs"
extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-archive-dsym.XXXXXX")"
trap '/bin/rm -rf "$extract_dir"' EXIT
/usr/bin/ditto -x -k "$archive/Ring-Stats.dSYM.zip" "$extract_dir"
archived_dsym="$extract_dir/Ring Stats.app.dSYM"
[[ -d "$archived_dsym" && ! -L "$archived_dsym" ]] || fail "Archive dSYM root is missing or linked"
while IFS= read -r -d '' link; do
  resolved="$(/usr/bin/realpath "$link" 2>/dev/null || true)"
  [[ -n "$resolved" && "$resolved" == "$extract_dir/"* ]] || fail "Archived dSYM symlink escapes extraction root: $link"
done < <(/usr/bin/find "$extract_dir" -type l -print0)
archived_uuids="$(/usr/bin/dwarfdump --uuid "$archived_dsym" | /usr/bin/sed -E 's/^UUID: ([^ ]+) \(([^)]+)\).*/\2:\1/' | LC_ALL=C /usr/bin/sort | /usr/bin/paste -sd, -)"
[[ "$archived_uuids" == "$(/bin/cat "$archive/uuids.txt")" ]] || fail "Archived dSYM UUIDs differ"
identity_file="$(mktemp "${TMPDIR:-/tmp}/ring-stats-archive-identity.XXXXXX")"
"$(cd "$(dirname "$0")" && pwd -P)/bundle_identity.sh" "$archived_dsym" "$identity_file"
[[ "$(/usr/bin/shasum -a 256 "$identity_file" | /usr/bin/awk '{print $1}')" == "$(/usr/bin/plutil -extract dsym_identity_sha256 raw "$archive/candidate-manifest.json")" ]] || fail "Archived dSYM identity differs from manifest"
/usr/bin/cmp -s "$identity_file" "$archive/dsym-identity.txt" || fail "Archived dSYM inventory differs"
/bin/rm -f "$identity_file"
while IFS= read -r -d '' extracted_file; do
  findings="$(/usr/bin/strings -a "$extracted_file" | /usr/bin/grep -E '/Users/[^/]+/|CLIENT_SECRET|APPLE_NOTARY_PROFILE|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' || true)"
  [[ -z "$findings" ]] || fail "Sensitive content found in archived dSYM: $extracted_file"
done < <(/usr/bin/find "$archived_dsym" -type f -print0)
echo "Verified immutable candidate archive: $archive"
