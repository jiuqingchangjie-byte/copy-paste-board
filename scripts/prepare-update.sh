#!/bin/bash
# Build no code here: sign and package the already accepted application.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_DIR/dist/ClipboardBoard.app}"
TOOLS="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"
ACCOUNT=com.local.clipboardboard
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
[[ "$VERSION" == "$SOURCE_VERSION" && "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Version mismatch.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print ClipboardBoardSourceSHA256' "$APP/Contents/Info.plist")" == "$(python3 "$PROJECT_DIR/scripts/build-inputs.py")" ]] || {
    echo 'App was built from different source or resources. Rebuild and verify it first.' >&2; exit 1;
}
KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")"
[[ "$KEY" == "$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)" ]] || { echo 'Wrong Sparkle signing key; original key required.' >&2; exit 1; }
ARCH="$(lipo -archs "$APP/Contents/MacOS/ClipboardBoard")"
[[ "$ARCH" == arm64 ]] || { echo 'This update channel currently supports arm64 only.' >&2; exit 1; }
NOTES="$PROJECT_DIR/docs/releases/v$VERSION.md"
[[ -s "$NOTES" ]] || { echo 'Release notes are required.' >&2; exit 1; }
mkdir -p "$PROJECT_DIR/dist/updates"
STAGE="$(mktemp -d "$PROJECT_DIR/dist/updates/.prepare.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
NAME="ClipboardBoard-v$VERSION-update-$ARCH"
ditto -c -k --noextattr --norsrc --keepParent "$APP" "$STAGE/$NAME.zip"
cp "$NOTES" "$STAGE/$NAME.md"
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/jiuqingchangjie-byte/copy-paste-board/releases/download/v$VERSION/" "$STAGE"
python3 "$PROJECT_DIR/scripts/verify-update.py" "$STAGE" "$APP"
(cd "$STAGE" && shasum -a 256 "$NAME.zip" appcast.xml > UPDATE-SHA256SUMS.txt)
DESTINATION="$PROJECT_DIR/dist/updates/v$VERSION"
mkdir -p "$DESTINATION"
cp "$STAGE/$NAME.zip" "$STAGE/appcast.xml" "$STAGE/UPDATE-SHA256SUMS.txt" "$DESTINATION/"
printf 'Prepared signed update assets: %s\n' "$DESTINATION"
