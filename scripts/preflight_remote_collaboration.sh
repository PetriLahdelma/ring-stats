#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
"$PROJECT_DIR/scripts/assert_production_environment.sh"
manifest="${1:-$PROJECT_DIR/dist/candidate-manifest.json}"

"$PROJECT_DIR/scripts/verify_approval_gate.sh" gate-a "$manifest"
echo "Remote-collaboration preflight passed for approved tree in: $manifest"
