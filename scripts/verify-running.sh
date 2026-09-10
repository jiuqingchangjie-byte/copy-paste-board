#!/bin/bash
# Fail before UI acceptance if the process is not the expected packaged build.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$PROJECT_DIR" "${1:?Usage: verify-running.sh EXPECTED_VERSION [APP_PATH] [REFERENCE_APP_PATH]}" "${2:-$PROJECT_DIR/dist/ClipboardBoard.app}" "${3:-$PROJECT_DIR/dist/ClipboardBoard.app}" <<'PY'
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

_, root, expected_version, app_path, reference_path = sys.argv
app = Path(app_path).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
reference = Path(reference_path).resolve()
expected_info = plistlib.loads((reference / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == expected_version, 'Disk version is not the requested version'
assert expected_info['CFBundleShortVersionString'] == expected_version
assert info['ClipboardBoardBuildID'] == expected_info['ClipboardBoardBuildID'], 'Installed app is not the build intended for this test'
executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
digest = hashlib.sha256(executable.read_bytes()).hexdigest()
expected_digest = hashlib.sha256((reference / 'Contents/MacOS' / expected_info['CFBundleExecutable']).read_bytes()).hexdigest()
assert digest == expected_digest, 'Installed binary differs from the intended build'
processes = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()
matching = [int(line.strip().split(None, 1)[0]) for line in processes
            if len(line.strip().split(None, 1)) == 2 and line.strip().split(None, 1)[1] == str(executable)]
assert len(matching) == 1, f'Expected one process at {executable}, found {len(matching)}'
pid = matching[0]
runtime_file = Path(tempfile.gettempdir()) / f'ClipboardBoard-runtime-{pid}.json'
assert runtime_file.exists(), 'Running process has no build identity; restart the intended app first'
runtime = json.loads(runtime_file.read_text())
assert runtime['pid'] == pid
assert Path(runtime['applicationPath']).resolve() == app
assert runtime['version'] == expected_version, 'Running version differs from disk version'
assert runtime['buildID'] == info['ClipboardBoardBuildID'], 'Old process: restart after rebuilding'
assert runtime['executableSHA256'] == digest, 'Running executable differs from the current build'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
signature = subprocess.run(['codesign', '-d', '-r-', str(app)], text=True, capture_output=True, check=True)
requirement = signature.stdout + signature.stderr
assert 'designated =>' in requirement and 'cdhash' not in requirement, 'A stable signing identity is required'
print(json.dumps(runtime, ensure_ascii=False, indent=2))
print('PASS: running path, version, build ID, executable hash, and signature match.')
PY
