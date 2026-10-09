# shellcheck shell=bash
# Shared helpers for the release and verification scripts. Source it after
# `set -euo pipefail`:
#   source "$(cd "$(dirname "$0")" && pwd -P)/lib/common.sh"

# A CDPATH would make `cd` print the directory it chose.
unset CDPATH

fail() {
  echo "error: $*" >&2
  exit 1
}

# A field from a JSON or plist file, or empty when it is absent.
read_field() { /usr/bin/plutil -extract "$2" raw "$1" 2>/dev/null || true; }

# The absolute path of a file whose directory exists.
canonical_path() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }

# The git tree hash of the working tree in $PROJECT_DIR, tracked and
# untracked files alike, without touching the real index.
working_tree_hash() {
  local index
  index="$(mktemp "${TMPDIR:-/tmp}/ring-stats-tree-index.XXXXXX")"
  GIT_INDEX_FILE="$index" /usr/bin/git -C "$PROJECT_DIR" read-tree HEAD
  GIT_INDEX_FILE="$index" /usr/bin/git -C "$PROJECT_DIR" add -A
  GIT_INDEX_FILE="$index" /usr/bin/git -C "$PROJECT_DIR" write-tree
  /bin/rm -f "$index"
}
