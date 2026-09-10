#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/ClipboardBoard.app"
IDENTITY="${CODE_SIGN_IDENTITY:-$(cat "$PROJECT_DIR/.codesign/identity.sha1")}"
REQUIREMENT="$(codesign -d -r- "$APP_DIR" 2>&1 | sed -n 's/^designated => //p')"
[[ -n "$REQUIREMENT" && "$REQUIREMENT" != *cdhash* ]]
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clipboardboard-signing-test.XXXXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto "$APP_DIR" "$VERIFY_DIR/ClipboardBoard.app"
/usr/libexec/PlistBuddy -c 'Set CFBundleVersion 999999' "$VERIFY_DIR/ClipboardBoard.app/Contents/Info.plist"
codesign --force --timestamp=none --sign "$IDENTITY" "$VERIFY_DIR/ClipboardBoard.app"
codesign --verify --strict -R "=$REQUIREMENT" "$VERIFY_DIR/ClipboardBoard.app"
NEXT_REQUIREMENT="$(codesign -d -r- "$VERIFY_DIR/ClipboardBoard.app" 2>&1 | sed -n 's/^designated => //p')"
[[ "$REQUIREMENT" == "$NEXT_REQUIREMENT" ]]
OLD_HASH="$(codesign -dvvv "$APP_DIR" 2>&1 | sed -n 's/^CDHash=//p')"
NEW_HASH="$(codesign -dvvv "$VERIFY_DIR/ClipboardBoard.app" 2>&1 | sed -n 's/^CDHash=//p')"
[[ -n "$OLD_HASH" && -n "$NEW_HASH" && "$OLD_HASH" != "$NEW_HASH" ]]
printf '通过：修改版本并重新签名后，仍满足旧版本的应用身份要求。\n'
