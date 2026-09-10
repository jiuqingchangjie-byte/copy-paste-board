#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY="$CODE_SIGN_IDENTITY"
elif [[ -f "$PROJECT_DIR/.codesign/identity.sha1" ]]; then
    SIGNING_IDENTITY="$(cat "$PROJECT_DIR/.codesign/identity.sha1")"
else
    printf '缺少固定签名身份。请先运行 scripts/setup-local-signing.sh --install，或设置 CODE_SIGN_IDENTITY。\n现有应用包未改变。\n' >&2
    exit 1
fi
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    printf '已禁用临时签名，防止每次更新丢失授权。请使用固定的代码签名证书。\n' >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fiq "$SIGNING_IDENTITY"; then
    printf '找不到有效的签名身份：%s。现有应用包未改变。\n' "$SIGNING_IDENTITY" >&2
    exit 1
fi
CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/ClipboardBoard.app"
mkdir -p "$PROJECT_DIR/dist"
BUILD_STAGE="$(mktemp -d "$PROJECT_DIR/dist/.clipboardboard-build.XXXXXXXX")"
STAGED_APP="$BUILD_STAGE/ClipboardBoard.app"
cleanup() {
    if [[ -d "$BUILD_STAGE/previous.app" && ! -d "$APP_DIR" ]]; then
        mv "$BUILD_STAGE/previous.app" "$APP_DIR"
    fi
    rm -rf "$BUILD_STAGE"
}
trap cleanup EXIT
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/ClipboardBoard" "$STAGED_APP/Contents/MacOS/ClipboardBoard"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
NEW_REQUIREMENT="$(codesign -d -r- "$STAGED_APP" 2>&1 | sed -n 's/^designated => //p')"
if [[ -z "$NEW_REQUIREMENT" || "$NEW_REQUIREMENT" == *cdhash* ]]; then
    printf '构建未得到固定签名身份，拒绝替换现有应用。\n' >&2
    exit 1
fi
if [[ -d "$APP_DIR" ]]; then
    OLD_REQUIREMENT="$(codesign -d -r- "$APP_DIR" 2>&1 | sed -n 's/^designated => //p')"
    if [[ -n "$OLD_REQUIREMENT" && "$OLD_REQUIREMENT" != *cdhash* && "$OLD_REQUIREMENT" != "$NEW_REQUIREMENT" ]]; then
        printf '签名身份发生变化，已停止构建以免破坏原授权。请使用原签名证书。\n' >&2
        exit 1
    fi
    mv "$APP_DIR" "$BUILD_STAGE/previous.app"
fi
mv "$STAGED_APP" "$APP_DIR"
printf '已生成：%s\n' "$APP_DIR"
