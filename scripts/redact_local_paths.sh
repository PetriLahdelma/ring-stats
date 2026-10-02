#!/bin/bash
# Rewrites absolute local paths in a release record directory: the checkout
# becomes "." and the home folder "~". Only text records (.txt, .json,
# .sha256) are rewritten; archives are left alone.
#
# Usage: redact_local_paths.sh <directory> <checkout-path> <home-path>
set -euo pipefail

directory="${1:?directory required}"
checkout="${2:?checkout path required}"
home="${3:?home path required}"
# An empty or root path would match everywhere and corrupt the records.
[[ "$checkout" == /?* && "$home" == /?* ]] || { echo "Refusing to redact with an empty or root path." >&2; exit 1; }

while IFS= read -r -d '' record; do
  CHECKOUT="$checkout" HOME_PATH="$home" /usr/bin/perl -pi -e \
    's/\Q$ENV{CHECKOUT}\E/./g; s/\Q$ENV{HOME_PATH}\E/~/g' "$record"
done < <(/usr/bin/find "$directory" -type f \( -name '*.txt' -o -name '*.json' -o -name '*.sha256' \) -print0)
