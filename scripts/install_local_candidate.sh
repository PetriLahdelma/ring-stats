#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/lib/common.sh"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_NAME="Ring Stats"
CANDIDATE_INPUT="${1:-$PROJECT_DIR/dist/$APP_NAME.app}"
if [[ "${RING_STATS_TEST_MODE:-0}" == "1" ]]; then
  [[ -n "${RING_STATS_TEST_ROOT:-}" ]] || { echo "error: RING_STATS_TEST_ROOT is required in test mode" >&2; exit 1; }
  TEST_ROOT="$(cd "$RING_STATS_TEST_ROOT" && pwd -P)"
  BUNDLE_ID="${BUNDLE_ID:-com.digitaltableteur.ringstats}"
  USER_APPLICATIONS_DIR="${USER_APPLICATIONS_DIR:-$HOME/Applications}"
  TRASH_DIR="${TRASH_DIR:-$HOME/.Trash}"
  FAIL_AT="${RING_STATS_INSTALL_FAIL_AT:-}"
  OSASCRIPT_BIN="${OSASCRIPT_BIN:-/usr/bin/osascript}"
  QUIT_RUNNING_CHECK_BIN="${QUIT_RUNNING_CHECK_BIN:-/usr/bin/osascript}"
  LAUNCH_RUNNING_CHECK_BIN="${LAUNCH_RUNNING_CHECK_BIN:-/usr/bin/osascript}"
  CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"
  LSREGISTER_BIN="${LSREGISTER_BIN:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
  MDIMPORT_BIN="${MDIMPORT_BIN:-/usr/bin/mdimport}"
  OPEN_BIN="${OPEN_BIN:-/usr/bin/open}"
else
  BUNDLE_ID="com.digitaltableteur.ringstats"
  USER_APPLICATIONS_DIR="$HOME/Applications"
  TRASH_DIR="$HOME/.Trash"
  FAIL_AT=""
  OSASCRIPT_BIN=/usr/bin/osascript
  QUIT_RUNNING_CHECK_BIN=/usr/bin/osascript
  LAUNCH_RUNNING_CHECK_BIN=/usr/bin/osascript
  CODESIGN_BIN=/usr/bin/codesign
  LSREGISTER_BIN=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  MDIMPORT_BIN=/usr/bin/mdimport
  OPEN_BIN=/usr/bin/open
fi
INSTALLED_APP="$USER_APPLICATIONS_DIR/$APP_NAME.app"


is_running() {
  local phase="$1"
  if [[ "${RING_STATS_TEST_MODE:-0}" == "1" ]]; then
    local checker="$QUIT_RUNNING_CHECK_BIN"
    [[ "$phase" == "launch" ]] && checker="$LAUNCH_RUNNING_CHECK_BIN"
    [[ "$("$checker" -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null || printf 'false')" == "true" ]]
  else
    [[ -n "$(/usr/bin/lsappinfo find "bundleID=$BUNDLE_ID" 2>/dev/null || true)" ]]
  fi
}

quit_exact_app() {
  "$OSASCRIPT_BIN" -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 &
  local quit_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ! is_running quit; then
      /bin/kill -TERM "$quit_pid" >/dev/null 2>&1 || true
      wait "$quit_pid" >/dev/null 2>&1 || true
      return 0
    fi
    /bin/sleep 0.1
  done
  /bin/kill -TERM "$quit_pid" >/dev/null 2>&1 || true
  wait "$quit_pid" >/dev/null 2>&1 || true
  if [[ "${RING_STATS_TEST_MODE:-0}" != "1" ]]; then
    local asn app_pid
    asn="$(/usr/bin/lsappinfo find "bundleID=$BUNDLE_ID" 2>/dev/null | /usr/bin/head -n 1 || true)"
    app_pid="$(/usr/bin/lsappinfo info -only pid "$asn" 2>/dev/null | /usr/bin/sed -nE 's/^"pid"=([0-9]+)$/\1/p')"
    if [[ -n "$app_pid" ]]; then
      echo "Ring Stats did not answer Quit; sending TERM to exact bundle process $app_pid." >&2
      /bin/kill -TERM "$app_pid"
      for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        is_running quit || return 0
        /bin/sleep 0.1
      done
    fi
  fi
  return 1
}

[[ -n "$CANDIDATE_INPUT" && ! "$CANDIDATE_INPUT" =~ [[:cntrl:]] ]] || fail "Unsafe candidate path"
[[ -d "$CANDIDATE_INPUT" ]] || fail "Missing candidate bundle: $CANDIDATE_INPUT"
[[ ! -L "$CANDIDATE_INPUT" ]] || fail "Candidate bundle must not be a symbolic link"
CANDIDATE_APP="$(cd "$(dirname "$CANDIDATE_INPUT")" && pwd -P)/$(basename "$CANDIDATE_INPUT")"
[[ -x "$CANDIDATE_APP/Contents/MacOS/RingStats" ]] || fail "Missing candidate executable"
for path_value in "$CANDIDATE_APP" "$USER_APPLICATIONS_DIR" "$TRASH_DIR" "$INSTALLED_APP"; do
  [[ -n "$path_value" && "$path_value" != "/" && "$path_value" != "." && "$path_value" != ".." ]] || fail "Refusing dangerous installation path"
  [[ ! "$path_value" =~ [[:cntrl:]] ]] || fail "Installation paths must not contain control characters"
done
[[ "$CANDIDATE_APP" != "$INSTALLED_APP" ]] || fail "Candidate and installed paths must differ"
if [[ "${RING_STATS_TEST_MODE:-0}" == "1" ]]; then
  [[ "$CANDIDATE_APP" == "$TEST_ROOT/"* && "$USER_APPLICATIONS_DIR" == "$TEST_ROOT/"* && "$TRASH_DIR" == "$TEST_ROOT/"* ]] \
    || fail "Test-mode paths must remain under RING_STATS_TEST_ROOT"
fi
candidate_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE_APP/Contents/Info.plist")"
[[ "$candidate_bundle_id" == "$BUNDLE_ID" ]] || fail "Unexpected candidate bundle identifier: $candidate_bundle_id"
"$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$CANDIDATE_APP"

/bin/mkdir -p "$USER_APPLICATIONS_DIR" "$TRASH_DIR"
[[ ! -L "$USER_APPLICATIONS_DIR" && ! -L "$TRASH_DIR" ]] || fail "Installation roots must not be symbolic links"
staging_dir="$(mktemp -d "$USER_APPLICATIONS_DIR/.ring-stats-install.XXXXXX")"
staged_app="$staging_dir/$APP_NAME.app"
backup_dir=""
installed_candidate=0
completed=0

preserve_staging() {
  if [[ -d "$staging_dir" ]]; then
    local preserved
    preserved="$(mktemp -d "$TRASH_DIR/Ring Stats incomplete install.XXXXXX")"
    /bin/rmdir "$preserved"
    /bin/mv "$staging_dir" "$preserved"
    echo "Incomplete candidate preserved at: $preserved" >&2
  fi
}

rollback() {
  local status=$?
  if [[ "$completed" -eq 0 ]]; then
    if [[ "$installed_candidate" -eq 1 && -d "$INSTALLED_APP" ]]; then
      quit_exact_app || true
      local failed_dir
      failed_dir="$(mktemp -d "$TRASH_DIR/Ring Stats failed candidate.XXXXXX")"
      /bin/mv "$INSTALLED_APP" "$failed_dir/$APP_NAME.app"
      echo "Failed candidate preserved at: $failed_dir/$APP_NAME.app" >&2
    fi
    if [[ -n "$backup_dir" && -d "$backup_dir/$APP_NAME.app" && ! -e "$INSTALLED_APP" ]]; then
      /bin/mv "$backup_dir/$APP_NAME.app" "$INSTALLED_APP"
      echo "Previous installation restored: $INSTALLED_APP" >&2
    fi
    preserve_staging
  fi
  exit "$status"
}
trap rollback EXIT

[[ "$FAIL_AT" != "stage" ]] || fail "Injected staging failure"
/usr/bin/ditto "$CANDIDATE_APP" "$staged_app"
"$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$staged_app"
[[ "$FAIL_AT" != "before_backup" ]] || fail "Injected failure before backup"

quit_exact_app || fail "$APP_NAME did not quit; refusing to replace a running application"

if [[ -e "$INSTALLED_APP" ]]; then
  backup_dir="$(mktemp -d "$TRASH_DIR/Ring Stats previous.XXXXXX")"
  /bin/mv "$INSTALLED_APP" "$backup_dir/$APP_NAME.app"
fi
[[ "$FAIL_AT" != "after_backup" ]] || fail "Injected failure after backup"

/bin/mv "$staged_app" "$INSTALLED_APP"
installed_candidate=1
/bin/rmdir "$staging_dir"
[[ "$FAIL_AT" != "after_copy" ]] || fail "Injected failure after copy"

"$LSREGISTER_BIN" -f "$INSTALLED_APP"
[[ "$FAIL_AT" != "after_register" ]] || fail "Injected failure after register"
"$MDIMPORT_BIN" -i "$INSTALLED_APP" >/dev/null 2>&1 || true
"$OPEN_BIN" "$INSTALLED_APP"
[[ "$FAIL_AT" != "after_open" ]] || fail "Injected failure after open"
launched=0
for _ in {1..20}; do
  if is_running launch; then
    launched=1
    break
  fi
  /bin/sleep 0.1
done
[[ "$launched" -eq 1 ]] || fail "$APP_NAME did not launch; restoring the previous installation"

completed=1
trap - EXIT
echo "Installed, registered, and launched: $INSTALLED_APP"
if [[ -n "$backup_dir" ]]; then
  echo "Previous version recovery path: $backup_dir/$APP_NAME.app"
else
  echo "Previous version recovery path: none (no prior installation)"
fi
