#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
TEST_FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    # Command Line Tools ship Swift Testing but do not expose it to swiftc by default.
    swift test --disable-xctest -Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$DEVELOPER_DIR_PATH/Library/Developer/usr/lib" "$@"
else
    swift test --disable-xctest "$@"
fi
