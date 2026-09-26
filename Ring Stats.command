#!/bin/zsh
set -e

PROJECT_DIR="${0:A:h}"
INSTALLED_APP_PATH="$HOME/Applications/Ring Stats.app"

if [[ ! -d "$INSTALLED_APP_PATH" ]]; then
  INSTALL_APP=1 "$PROJECT_DIR/scripts/build_app.sh"
fi

open "$INSTALLED_APP_PATH"
