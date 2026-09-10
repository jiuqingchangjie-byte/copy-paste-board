#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -d "$PROJECT_DIR/dist/ClipboardBoard.app" ]]; then
    "$PROJECT_DIR/scripts/build-app.sh"
fi
open "$PROJECT_DIR/dist/ClipboardBoard.app"
