#!/bin/bash
# Fails if a release archive, including archives nested inside it, contains a
# local home-folder or temporary-folder path, written plainly or JSON-escaped
# ("\/Users\/..."), which would reveal the maintainer's account name and
# folder layout.
#
# Usage: verify_no_local_paths.sh <archive.zip>
set -euo pipefail

archive="${1:?archive required}"
work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ring-stats-paths.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT

/usr/bin/ditto -x -k "$archive" "$work/root"
# Expand nested archives, such as the zipped dSYM, so they are scanned too.
while IFS= read -r -d '' nested; do
  /usr/bin/ditto -x -k "$nested" "${nested%.zip}.contents"
done < <(/usr/bin/find "$work/root" -type f -name '*.zip' -print0)

findings="$(/usr/bin/find "$work/root" -type f -print0 \
  | /usr/bin/xargs -0 /usr/bin/grep -a -l -E '\\?/Users\\?/[A-Za-z0-9._-]+|\\?/(private\\?/)?var\\?/folders\\?/' 2>/dev/null || true)"
if [[ -n "$findings" ]]; then
  echo "FAIL: local paths found in $(basename "$archive"):" >&2
  echo "$findings" | /usr/bin/sed "s|$work/root/|  |" >&2
  exit 1
fi
echo "No local paths in $(basename "$archive")"
