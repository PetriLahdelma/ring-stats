#!/bin/zsh
set -e

PROJECT_DIR="${0:A:h}"
INSTALLED_APP_PATH="$HOME/Applications/Ring Stats.app"
INSTALLED_EXECUTABLE="$INSTALLED_APP_PATH/Contents/MacOS/RingStats"

if [[ ! -x "$INSTALLED_EXECUTABLE" ]] || find \
  "$PROJECT_DIR/Sources" \
  "$PROJECT_DIR/Package.swift" \
  "$PROJECT_DIR/native" \
  "$PROJECT_DIR/scripts/build_app.sh" \
  "$PROJECT_DIR/scripts/install_local_candidate.sh" \
  "$PROJECT_DIR/scripts/emit_candidate_manifest.sh" \
  -newer "$INSTALLED_EXECUTABLE" -print -quit | grep -q .; then
  INSTALL_APP=1 "$PROJECT_DIR/scripts/build_app.sh"
fi

open "$INSTALLED_APP_PATH"
