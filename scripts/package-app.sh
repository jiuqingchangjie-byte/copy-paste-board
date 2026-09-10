#!/bin/bash
# Package an existing, tested app without rebuilding or changing its identity.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_DIR/dist/ClipboardBoard.app}"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
[[ "$VERSION" == "$SOURCE_VERSION" ]] || { echo 'App version differs from source version.' >&2; exit 1; }
ARCH="$(lipo -archs "$APP/Contents/MacOS/ClipboardBoard")"
case "$ARCH" in
    arm64|x86_64) ;;
    'x86_64 arm64'|'arm64 x86_64') ARCH=universal ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
NAME="ClipboardBoard-v$VERSION-macos-$ARCH"
mkdir -p "$PROJECT_DIR/dist"
STAGE="$(mktemp -d "$PROJECT_DIR/dist/.clipboardboard-package.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME"
ditto --noextattr --norsrc "$APP" "$STAGE/$NAME/ClipboardBoard.app"
cp "$PROJECT_DIR/docs/INSTALL_APP.md" "$STAGE/$NAME/INSTALL.md"
cp "$PROJECT_DIR/LICENSE" "$STAGE/$NAME/LICENSE"
codesign --verify --deep --strict "$STAGE/$NAME/ClipboardBoard.app"
ditto -c -k --noextattr --norsrc --keepParent "$STAGE/$NAME" "$PROJECT_DIR/dist/$NAME.zip"
cd "$PROJECT_DIR/dist"
shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256"
printf '已生成可直接解压安装的未公证应用包：%s/%s.zip\n' "$PWD" "$NAME"
