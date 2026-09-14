#!/bin/bash
# Copy the resolved dependency, preserving framework symlinks. Sign inside out.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?Usage: embed-sparkle.sh APP SIGNING_IDENTITY}"
IDENTITY="${2:?Signing identity required}"
SOURCE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SOURCE" && -d "$APP/Contents" ]] || { echo 'Sparkle or destination app missing.' >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SOURCE" "$APP/Contents/Frameworks/Sparkle.framework"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SIGN_OPTIONS=(--timestamp=none)
if [[ "$IDENTITY" == 'Developer ID Application:'* ]]; then SIGN_OPTIONS=(--options runtime --timestamp); fi
for helper in "$FRAMEWORK"/Versions/B/XPCServices/*.xpc "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK/Versions/B/Autoupdate"; do
    codesign --force "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" "$helper"
done
codesign --force "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" "$FRAMEWORK"
codesign --verify --deep --strict "$FRAMEWORK"
cp "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
