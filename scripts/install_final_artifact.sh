#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
"$PROJECT_DIR/scripts/assert_production_environment.sh"
artifact="${1:-}"
[[ -f "$artifact" && ! -L "$artifact" ]] || { echo "Usage: $0 <final-notarized-dmg>" >&2; exit 1; }
/usr/bin/codesign --verify --verbose=2 "$artifact"
xcrun stapler validate "$artifact"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$artifact"
mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/ring-stats-final-install.XXXXXX")"
cleanup() { /usr/bin/hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true; /bin/rmdir "$mount_dir" >/dev/null 2>&1 || true; }
trap cleanup EXIT
/usr/bin/hdiutil attach "$artifact" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
"$PROJECT_DIR/scripts/install_local_candidate.sh" "$mount_dir/Ring Stats.app"
cleanup
trap - EXIT
evidence="$(mktemp "${TMPDIR:-/tmp}/ring-stats-final-evidence.XXXXXX.plist")"
trap '/bin/rm -f "$evidence"' EXIT
"$PROJECT_DIR/scripts/verify_final_artifact.sh" "$artifact" "$HOME/Applications/Ring Stats.app" "$evidence"
echo "Installed and verified exact final artifact: $artifact"
