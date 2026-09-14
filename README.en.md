# ClipboardBoard

[中文](README.md) | **English**

A native macOS menu bar clipboard history app. Press **⌥ Option + V** to find recently copied text, images, and files, select an entry with the arrow keys, and press Return to paste into the original application.

Its compact card list is inspired by Windows clipboard history and supports light and dark appearances. Built with Swift and AppKit, with no third-party package dependencies, accounts, or network services. Current version: **1.6.1**, with Simplified Chinese, English, Japanese, and Korean interfaces and the same compact history panel size in every language.

## Download the app

[Download v1.6.1 for Apple Silicon / M-series Macs](https://github.com/jiuqingchangjie-byte/copy-paste-board/releases/download/v1.6.1/ClipboardBoard-v1.6.1-macos-arm64.zip)

Extract the ZIP, move `ClipboardBoard.app` to `Applications` inside your home folder (`~/Applications`), and open it. No source build, Xcode, signing tools, or Apple Developer membership is needed. Bilingual installation instructions are included.

The app uses a stable self-signed certificate and **is not notarized by Apple**. If the developer cannot be verified, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway** and grant Accessibility access when prompted. [Installation guide](docs/INSTALL_APP.md) · [Release and checksums](https://github.com/jiuqingchangjie-byte/copy-paste-board/releases/tag/v1.6.1)

## Features

- **Interface languages:** choose Chinese, English, Japanese, or Korean in **More Options → Language**. Changes apply immediately and persist across restarts; copied content remains unchanged. [Usage and acceptance](docs/LANGUAGES.md).

- **Independent favorites:** save from history stars, organize folders, search, move/remove multiple selections, or clear a folder/library. Favorites do not consume history capacity and have no 50-item count limit. [Design and acceptance](docs/FAVORITES_AND_STORAGE.md).
- **Configurable storage:** migrate history, favorites, and settings to a chosen directory; verify before switching and retain the old copy. Restart restores committed data.

- **JSON formatting:** format JSON in full-text previews and restore the exact original. Preserve number precision, duplicate keys, order, and escapes. Viewing never changes the clipboard or history. [Acceptance](docs/JSON_PREVIEW.md).
- **Full previews:** hover for one second (configurable from 0.2 to 5 seconds), scroll complete text, and explicitly copy a selection into history. View original images, zoom, pin above other windows, and drag their header. Search spaces remain text input; Esc restores the original history selection. [Behavior and acceptance](docs/PREVIEW.md).
- **Content capture:** plain text, PNG/TIFF images, and local Finder file references.
- **Custom shortcuts:** explicitly record, save, or restore Option-V. Failed saves keep the previous registration. [Usage and acceptance](docs/CUSTOM_SHORTCUT.md).
- **Keyboard workflow:** global shortcut, arrow-key selection, Return to paste, and Esc to dismiss; double-click also works.
- **Search and deduplication:** search content, file paths, or source application names; repeated content moves to the top.
- **Configurable history:** keep the latest 10 entries by default, adjustable from 1 to 50; the oldest entries are evicted.
- **Local persistence:** restore history and favorites from the default adjacent `ClipboardBoardData` folder or a configured location.
- **Window and startup controls:** drag the header to save the panel position; enable launch at login with system approval status.
- **Paste safeguards:** wait for key release and attempt to restore the original window and input focus; cancel pending work when permissions, application focus, or clipboard contents change.
- **Diagnostics:** inspect paste permissions, the target application, and the latest result without reading input-field text.

## Requirements

| Purpose | Requirement |
| --- | --- |
| Run the app | macOS 13 or later |
| Build from source | macOS, Xcode or Command Line Tools, Swift 5.9+ |
| Run tests | macOS 14+, Swift 6+; Python 3 for build workflow tests |
| Package a `.app` | A valid, stable code-signing identity; see below |

The build script targets the host architecture rather than producing a universal binary. The project has been verified on Apple Silicon; Intel and the minimum supported macOS version still require separate validation.

## Build and install

The setup below is for developers building from source. End users can download the app above without generating certificates or configuring a development environment.

After building locally, install at a stable location:

```bash
./scripts/install-app.sh
open "$HOME/Applications/ClipboardBoard.app"
```

Quit before running the installer for subsequent updates. It validates signing identity, preserves destination data, and never resets privacy permissions. Local upgrades from 1.2.4 to 1.2.5 and same-identity reinstalls retained existing permissions. Initial use still requires consent; permission revocation, system resets, or identity changes may require it again.

### 1. Clone the repository

```bash
git clone git@github.com:jiuqingchangjie-byte/copy-paste-board.git
cd copy-paste-board
```

SSH cloning requires a public key configured on GitHub. HTTPS is also available:

```bash
git clone https://github.com/jiuqingchangjie-byte/copy-paste-board.git
cd copy-paste-board
```

### 2. Prepare a stable signing identity

For first-time local development:

```bash
# Generate local signing materials without changing the Keychain.
./scripts/setup-local-signing.sh --prepare

# Import into the login Keychain and configure user-level trust for code signing only.
./scripts/setup-local-signing.sh --install
```

Complete any macOS Keychain prompts during installation. Signing materials live in `.codesign/`, which is excluded from Git. After a successful import, the temporary private-key package and wrapping password file are removed. Reuse the same identity for subsequent builds; do not delete or regenerate the original certificate.

### 3. Build and open the app

```bash
./scripts/build-app.sh
open dist/ClipboardBoard.app
```

If you already have a valid code-signing identity, skip step 2 and use this build command instead:

```bash
CODE_SIGN_IDENTITY="Your code-signing certificate name or SHA-1 fingerprint" ./scripts/build-app.sh
open dist/ClipboardBoard.app
```

Missing or unexpectedly changed signing identities stop the build workflow while preserving the existing app bundle. Once built, `./scripts/run.sh` launches the existing app without rebuilding. After an update, quit the old process before opening the new version.

The compiled download uses a stable self-signed certificate and can be distributed on GitHub without Apple Developer membership. macOS still controls first-open checks. Developer ID signing and notarization remain an optional future distribution path; see [installation and distribution](docs/INSTALLATION.md).

## Usage

Place the cursor in the target application's input field before opening history.

| Action | Shortcut or control |
| --- | --- |
| Toggle history | **⌥V**, or click the menu bar icon |
| Select an entry | **↑ / ↓** |
| Paste the selected entry | **Return**, or double-click the desired card |
| Dismiss the panel | **Esc**, or click outside |
| Delete the selected entry | **⌘Delete** |
| Search | Type after opening the panel |
| Change the history limit | **… → 历史记录上限** |
| Pause / resume capture | **…** menu, or right-click the menu bar icon |
| Launch at login | **… → 登录时自动启动** |
| Clear history | **全部清空** in the header, or the clear menu item |

Double-click uses the clicked card even if another entry was selected. Drag the title, icon, or empty header space to move the panel; the clear and menu buttons remain clickable. Pasting a history entry does not add an entry or change the copy order.

### Paste permissions

Use **去授权** in the panel to open **System Settings → Privacy & Security → Accessibility**, then allow the current ClipboardBoard app.

With Accessibility access, the app first attempts the target application's native Paste menu command. Permission to post keyboard events provides an alternative path; both permissions are not required together. History capture and browsing work without these permissions, but Return and double-click report that pasting is unavailable instead of silently becoming copy-only actions.

If the native Paste menu is missing or disabled, the app attempts one Command-V fallback only while keyboard-event permission, the original target focus, released keys, and clipboard contents remain valid. A successful or uncertain menu action never triggers a second paste. Inspect the original request target and failure stage through **… → 粘贴诊断**. Restoring the original input field and receiving the content still depend on the target application's support.

### Launch at login

Use the packaged `.app` from a stable location writable by the current user. Running only `swift run` cannot register the login item. If the menu shows **等待系统批准 · 尚未生效** (awaiting system approval; not active), use **去设置** to approve it, or turn the switch off to cancel the request.

## Data and privacy

Custom storage is recorded in `ClipboardBoardConfig/storage-location.json` beside the app. Preserve this folder during updates and moves. Missing custom storage produces an error rather than an empty fallback. External cloud/network software may sync selected folders; the app itself does not initiate networking. Favorites use SQLite transactions and full synchronization; JSON files are flushed before atomic replacement. Copies not yet captured or flushed cannot be guaranteed after a crash.

```text
Installation directory/
├── ClipboardBoard.app
└── ClipboardBoardData/
    ├── history.json
    ├── settings.json
    └── favorites.sqlite
```

- History stores full text, image data, and file URLs. Referenced files themselves are not copied into history.
- Files are written atomically. Directory permissions are `0700`; data-file permissions are `0600`. Contents are not additionally encrypted.
- The installation directory must be writable. Move `ClipboardBoardData` alongside the app when relocating it. Use **… → 打开数据目录** to reveal its location.
- Legacy Application Support data is migrated when possible. Existing new data, including cleared history, takes precedence. A failed migration preserves the original file and displays a message.
- History and settings have explicit format versions and remain compatible with legacy files. Old limits and histories above 50 are normalized to 50.
- Use **… → 数据与恢复** to retry failed reads/writes. Explicit recovery archives damaged originals under `Recovery/` before rebuilding them. Archives are never imported automatically, and recovery respects deletions and clearing in the current session. Newer format versions are never rebuilt.
- Recognized transient, concealed, autogenerated, and password-manager clipboard markers are filtered. Sensitive content without those markers may still be recorded.
- Clearing history saves an empty list without changing the current system clipboard. Deletion and clearing currently have no undo action.
- Content copied before launch or while paused is not collected retroactively. Pause state does not persist across restarts.
- `.gitignore` excludes history directories, signing materials, and build output.

## Known limitations

- Text is restored as plain text; HTML / RTF formatting is not retained.
- Each entry is limited to **8 MiB**; larger entries are skipped. Normal eviction follows the configured entry count, without a total-byte eviction threshold.
- Clipboard changes are polled approximately every **0.3 seconds**, so very rapid copies may only capture the last value.
- The global shortcut defaults to **⌥V** and can be customized. System shortcuts and exclusive registrations are checked; app-local shortcuts and nonexclusive listeners cannot all be enumerated. The menu bar remains available.
- File references may stop working if the original files are moved or deleted.
- History uses a single JSON file rewritten on each change. Large image histories can increase disk usage, memory consumption, and startup cost.
- Cross-device sync and automatic updates are not implemented. Pinned image windows are session-only viewers; save to favorites for long-term retention.

## Development and verification

```bash
# Compile without installing certificates or launching the app.
swift build -c release

# Swift model, clipboard, UI, and paste state-machine tests.
./scripts/test.sh

# Build and launch workflow tests using temporary directories and fake tools.
python3 -m unittest discover -s Tests/Scripts -p 'test_*.py'
```

The current baseline contains **127 Swift tests and 8 build/install workflow tests**. Tests use sample data and isolated pasteboards. Paste environments are mocked and do not send keystrokes to user applications.

Optionally render AppKit light / dark layout previews:

```bash
CLIPBOARD_PREVIEW_DIR="$PWD/.build/previews" ./scripts/test.sh
```

With a signed app and its matching identity available, verify identity continuity across updates:

```bash
./scripts/verify-signing.sh
```

This script modifies and re-signs a temporary copy without replacing the original app. Supply `CODE_SIGN_IDENTITY` when using a custom certificate.

Before each live acceptance run, verify the process against the intended build, specifying its installed location when necessary:

```bash
./scripts/verify-running.sh 1.6.1 "$HOME/Applications/ClipboardBoard.app"
```

The check compares the running path, version, build ID, executable hash, and signature with the current `dist` build. Even an older build with the same version number is rejected.

Swift 6.4's default test engine skipped this project's core suite, so the test script explicitly uses the native runner and supplies the CLT macro plugin path. Automated tests do not establish cross-application compatibility. See the [acceptance record](docs/ACCEPTANCE.md) for evidence and outstanding scenarios.

## Project structure

```text
Sources/ClipboardCore/    History model, settings, storage, and migration
Sources/ClipboardBoard/   AppKit panel, hotkey, capture, paste, and login service
Tests/                    Swift tests and Python build workflow tests
Resources/Info.plist      App identity, version, and minimum macOS version
scripts/                  Signing setup, build, launch, and verification
```

See [CHANGELOG.md](CHANGELOG.md) for version history.

Development planning: [TODO](TODO.md) · [data recovery experience](docs/DATA_RECOVERY.md) · [installation and distribution](docs/INSTALLATION.md).

## License

This project is licensed under the [Apache License 2.0](LICENSE).
