#!/bin/bash
# Explicit publisher action: publish only after all signed assets are present.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
command -v gh >/dev/null || { echo 'Install GitHub CLI (gh) and authenticate before publishing.' >&2; exit 1; }
REPO=jiuqingchangjie-byte/copy-paste-board
APP="$PROJECT_DIR/dist/ClipboardBoard.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit all release changes first.' >&2; exit 1; }
[[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse HEAD)" ]] || { echo 'Tag must match the current commit.' >&2; exit 1; }
REMOTE_COMMIT="$(git ls-remote origin "refs/tags/$TAG^{}" | cut -f1)"
[[ "$REMOTE_COMMIT" == "$(git rev-parse HEAD)" ]] || { echo 'Push the annotated release tag first.' >&2; exit 1; }
"$PROJECT_DIR/scripts/package-app.sh" "$APP"
"$PROJECT_DIR/scripts/prepare-update.sh" "$APP"
DIR="$PROJECT_DIR/dist/updates/$TAG"
PREVIOUS_TAG="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
[[ "$PREVIOUS_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Unexpected latest release tag.' >&2; exit 1; }
gh api "repos/$REPO/contents/Resources/Info.plist?ref=$PREVIOUS_TAG" > "$DIR/previous-info.json"
python3 "$PROJECT_DIR/scripts/verify-release-assets.py" --versions "$APP/Contents/Info.plist" "$DIR/previous-info.json"
SOURCE="ClipboardBoard-$TAG-source.zip"
git archive --format=zip --prefix="ClipboardBoard-$TAG/" "$TAG" > "$DIR/$SOURCE"
(cd "$DIR" && shasum -a 256 "$SOURCE" > SHA256SUMS.txt)
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "$TAG" --repo "$REPO" --verify-tag --draft \
        --title "ClipboardBoard $TAG" --notes-file "docs/releases/$TAG.md"
fi
[[ "$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft)" == true ]] || {
    echo 'Release is already public; refusing to replace its signed update assets.' >&2; exit 1;
}
ASSETS=("$PROJECT_DIR/dist/ClipboardBoard-$TAG-macos-arm64.zip"
    "$PROJECT_DIR/dist/ClipboardBoard-$TAG-macos-arm64.zip.sha256"
    "$DIR/ClipboardBoard-$TAG-update-arm64.zip" "$DIR/appcast.xml" "$DIR/UPDATE-SHA256SUMS.txt"
    "$DIR/$SOURCE" "$DIR/SHA256SUMS.txt")
gh release upload "$TAG" --repo "$REPO" --clobber "${ASSETS[@]}"
gh api "repos/$REPO/releases/tags/$TAG" > "$DIR/remote-assets.json"
python3 "$PROJECT_DIR/scripts/verify-release-assets.py" "$DIR/remote-assets.json" "${ASSETS[@]}"
# This final step makes the feed visible at releases/latest/download/appcast.xml.
gh release edit "$TAG" --repo "$REPO" --draft=false --latest \
    --title "ClipboardBoard $TAG" --notes-file "docs/releases/$TAG.md"
gh release view "$TAG" --repo "$REPO" --json url --jq .url
