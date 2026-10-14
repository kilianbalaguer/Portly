#!/bin/zsh
# Builds (or tests) Portly from the command line.
#   ./build.sh            Debug build
#   ./build.sh Release    Release build
#   ./build.sh test       run the unit tests
set -uo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Xcode 26.5's new swift-driver crashes (SIGILL) on some Intel Macs; the legacy driver is unaffected.
if [[ "$(uname -m)" == "x86_64" ]]; then export SWIFT_USE_OLD_DRIVER=1; fi

log=$(mktemp -t portly-build)
if [[ "${1:-}" == "test" ]]; then
  xcodebuild -project Portly.xcodeproj -scheme Portly -derivedDataPath build/DerivedData test > "$log" 2>&1
  code=$?
  grep -E "error:|failed|Executed .* tests|TEST (SUCCEEDED|FAILED)" "$log" | grep -v "legacy driver" | tail -20
else
  xcodebuild -project Portly.xcodeproj -scheme Portly -configuration "${1:-Debug}" \
    -derivedDataPath build/DerivedData build > "$log" 2>&1
  code=$?
  grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" "$log" | grep -v -e "legacy driver" -e "AppIntents" | sort -u
fi
if [[ $code -ne 0 ]]; then echo "--- last lines of $log ---"; tail -25 "$log"; fi
exit $code
