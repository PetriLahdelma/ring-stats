#!/bin/bash
set -euo pipefail

bundle="${1:-}"
output="${2:-}"
[[ -d "$bundle" && ! -L "$bundle" && -n "$output" ]] || { echo "Usage: $0 <bundle> <output>" >&2; exit 1; }
root="$(cd "$bundle" && pwd -P)"
: > "$output"
printf 'D\t%s\t.\t-\n' "$(/usr/bin/stat -f '%Lp' "$root")" >> "$output"
while IFS= read -r -d '' path; do
  relative="${path#"$root"/}"
  [[ "$relative" != *$'\n'* && "$relative" != *$'\r'* && "$relative" != *$'\t'* ]] || { echo "error: unsafe bundle path" >&2; exit 1; }
  mode="$(/usr/bin/stat -f '%Lp' "$path")"
  if [[ -L "$path" ]]; then
    printf 'L\t%s\t%s\t%s\n' "$mode" "$relative" "$(/usr/bin/readlink "$path")" >> "$output"
  elif [[ -f "$path" ]]; then
    printf 'F\t%s\t%s\t%s\n' "$mode" "$relative" "$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}')" >> "$output"
  elif [[ -d "$path" ]]; then
    printf 'D\t%s\t%s\t-\n' "$mode" "$relative" >> "$output"
  fi
done < <(/usr/bin/find "$root" -mindepth 1 -print0)
LC_ALL=C /usr/bin/sort -o "$output" "$output"
