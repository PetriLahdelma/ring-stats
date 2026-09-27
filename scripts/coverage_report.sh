#!/bin/bash
# Runs the test suite with coverage and prints line coverage grouped by the
# architectural boundaries in ARCHITECTURE.md. It reports; it does not enforce a
# target, because coverage percentage is not a quality goal in itself.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_DIR"

bin_path="$(swift build --show-bin-path)"
codecov_dir="$bin_path/codecov"
/bin/rm -rf "$codecov_dir"
swift test --enable-code-coverage -Xswiftc -warnings-as-errors >/dev/null
# Swift Testing leaves raw profiles; merge them explicitly.
profile="$codecov_dir/merged.profdata"
xcrun llvm-profdata merge -sparse "$codecov_dir"/*.profraw -o "$profile"
binary="$bin_path/RingStatsPackageTests.xctest/Contents/MacOS/RingStatsPackageTests"

xcrun llvm-cov export -summary-only -instr-profile "$profile" "$binary" \
  -ignore-filename-regex='(\.build|Tests)/' \
  | /usr/bin/python3 "$PROJECT_DIR/scripts/coverage_boundaries.py"
