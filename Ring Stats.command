#!/bin/zsh
set -e

PROJECT_DIR="${0:A:h}"
APP_PATH="$PROJECT_DIR/dist/Ring Stats.app"
INSTALLED_APP_PATH="$HOME/Applications/Ring Stats.app"

if [[ ! -d "$APP_PATH" || ! -d "$INSTALLED_APP_PATH" ]]; then
  "$PROJECT_DIR/scripts/build_app.sh"
fi

open "$INSTALLED_APP_PATH"
