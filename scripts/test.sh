#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
TEST_FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
# Swift 6.4's SwiftBuild engine currently discovers only the executable-target
# suite here (46 tests), skipping ClipboardCoreTests. Use the native runner so
# every declared test target is executed, including storage and recovery.
BUILD_FLAGS=(--build-system native)
MACRO_FLAGS=()
TEST_MACROS="$DEVELOPER_DIR_PATH/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TEST_MACROS" ]]; then
    # Swift 6.4 CLT places TestingMacros in a nested directory that is not
    # automatically passed to every test target by the new build engine.
    MACRO_FLAGS=(-Xswiftc -load-plugin-library -Xswiftc "$TEST_MACROS")
fi
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    # Command Line Tools ship Swift Testing but do not expose it to swiftc by default.
    swift test "${BUILD_FLAGS[@]}" --disable-xctest ${MACRO_FLAGS[@]+"${MACRO_FLAGS[@]}"} -Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$DEVELOPER_DIR_PATH/Library/Developer/usr/lib" "$@"
else
    swift test "${BUILD_FLAGS[@]}" --disable-xctest ${MACRO_FLAGS[@]+"${MACRO_FLAGS[@]}"} "$@"
fi
