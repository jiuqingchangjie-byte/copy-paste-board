#!/bin/bash
# Install an already signed app at a stable path. Never generate identities,
# reset privacy permissions, or touch the user's clipboard history on update.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:-$PROJECT_DIR/dist/ClipboardBoard.app}"
DEST_APP="${2:-$HOME/Applications/ClipboardBoard.app}"
[[ "$SOURCE_APP" == *.app && "$DEST_APP" == *.app ]] || { echo 'Source and destination must be .app bundles.' >&2; exit 1; }
[[ -d "$SOURCE_APP" && ! -L "$DEST_APP" ]] || { echo 'Source missing or destination is a symbolic link.' >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE_APP"
SOURCE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
[[ "$SOURCE_ID" == 'com.local.clipboardboard' ]] || { echo 'Unexpected app identifier.' >&2; exit 1; }
NEW_REQUIREMENT="$(codesign -d -r- "$SOURCE_APP" 2>&1 | sed -n 's/^designated => //p')"
[[ -n "$NEW_REQUIREMENT" && "$NEW_REQUIREMENT" != *cdhash* ]] || { echo 'A stable code-signing identity is required.' >&2; exit 1; }
mkdir -p "$(dirname "$DEST_APP")"
SOURCE_REAL="$(cd "$SOURCE_APP" && pwd -P)"
DEST_REAL="$(cd "$(dirname "$DEST_APP")" && pwd -P)/$(basename "$DEST_APP")"
[[ "$SOURCE_REAL" != "$DEST_REAL" ]] || { echo "Already installed: $DEST_REAL"; exit 0; }
if ps -axo comm= | /usr/bin/grep -Fxq "$DEST_REAL/Contents/MacOS/ClipboardBoard"; then
    echo '请先从菜单退出正在运行的目标应用，再安装更新。Quit the target app before updating.' >&2
    exit 1
fi
if [[ -d "$DEST_APP" ]]; then
    OLD_REQUIREMENT="$(codesign -d -r- "$DEST_APP" 2>&1 | sed -n 's/^designated => //p')"
    [[ -n "$OLD_REQUIREMENT" ]] || { echo 'Existing app identity could not be verified.' >&2; exit 1; }
    codesign --verify --strict -R "=$OLD_REQUIREMENT" "$SOURCE_APP"
fi
STAGE="$(mktemp -d "$(dirname "$DEST_APP")/.clipboardboard-install.XXXXXXXX")"
cleanup() {
    if [[ -d "$STAGE/previous.app" && ! -d "$DEST_APP" ]]; then mv "$STAGE/previous.app" "$DEST_APP"; fi
    rm -rf "$STAGE"
}
trap cleanup EXIT
ditto "$SOURCE_APP" "$STAGE/ClipboardBoard.app"
codesign --verify --deep --strict "$STAGE/ClipboardBoard.app"
# Import portable data only on first install, and never overwrite existing data.
SOURCE_DATA="$(dirname "$SOURCE_APP")/ClipboardBoardData"
DEST_DATA="$(dirname "$DEST_APP")/ClipboardBoardData"
if [[ ! -e "$DEST_APP" && -d "$SOURCE_DATA" && ! -e "$DEST_DATA" ]]; then
    ditto "$SOURCE_DATA" "$STAGE/ClipboardBoardData"
    chmod -R go-rwx "$STAGE/ClipboardBoardData"
    mv "$STAGE/ClipboardBoardData" "$DEST_DATA"
fi
if [[ -d "$DEST_APP" ]]; then mv "$DEST_APP" "$STAGE/previous.app"; fi
mv "$STAGE/ClipboardBoard.app" "$DEST_APP"
printf '已安装 / Installed: %s\n使用同一路径和签名更新，无需重置授权。\n' "$DEST_APP"
