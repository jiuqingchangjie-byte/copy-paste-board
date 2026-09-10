#!/bin/bash
# Publisher-only workflow. End users never import a development certificate.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${CODE_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set a preconfigured notarytool Keychain profile name}"
[[ "$CODE_SIGN_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Developer ID Application certificate required for distribution.' >&2; exit 1; }
security find-identity -v -p codesigning | grep -Fq "$CODE_SIGN_IDENTITY" || { echo 'Signing identity unavailable.' >&2; exit 1; }
cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p dist
STAGE="$(mktemp -d "$PROJECT_DIR/dist/.clipboardboard-release.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ClipboardBoard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClipboardBoard" "$APP/Contents/MacOS/ClipboardBoard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add ClipboardBoardBuildID string $(uuidgen)" "$APP/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
xcrun notarytool submit "$STAGE/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
ditto -c -k --keepParent "$APP" "$STAGE/ClipboardBoard-$VERSION-$ARCH.zip"
mv "$STAGE/ClipboardBoard-$VERSION-$ARCH.zip" "dist/ClipboardBoard-$VERSION-$ARCH.zip"
shasum -a 256 "dist/ClipboardBoard-$VERSION-$ARCH.zip"
