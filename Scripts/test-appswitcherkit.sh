#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="${1:-$ROOT_DIR/Libraries/AppSwitcherKit}"
DEVELOPER_ROOT="${DEVELOPER_DIR:-$(xcode-select -p)}"
TESTING_FRAMEWORKS="$DEVELOPER_ROOT/Library/Developer/Frameworks"
TESTING_LIBRARIES="$DEVELOPER_ROOT/Library/Developer/usr/lib"
TESTING_PLUGINS="$DEVELOPER_ROOT/usr/lib/swift/host/plugins/testing"

args=(
  --package-path "$PACKAGE_DIR"
  --enable-swift-testing
  --disable-xctest
)

# Some Command Line Tools releases ship Swift Testing outside swiftc's default
# search paths. Apply these flags globally so SwiftPM's generated runner can
# import Testing as well as the test target itself.
if [[ -d "$TESTING_FRAMEWORKS/Testing.framework" && -d "$TESTING_PLUGINS" ]]; then
  args+=(
    -Xswiftc -F -Xswiftc "$TESTING_FRAMEWORKS"
    -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS"
    -Xlinker -F -Xlinker "$TESTING_FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$TESTING_FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$TESTING_LIBRARIES"
  )
fi

exec swift test "${args[@]}"
