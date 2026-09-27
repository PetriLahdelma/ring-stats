#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
"$PROJECT_DIR/scripts/assert_production_environment.sh"
artifact="${1:-}"

if [[ -z "$artifact" ]]; then
  echo "Usage: $0 <final-notarized-artifact>" >&2
  exit 1
fi

"$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-b "$artifact"
echo "Publication preflight passed for exact approved artifact: $artifact"
