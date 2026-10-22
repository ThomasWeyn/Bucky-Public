#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "Bucky requires an Apple Silicon Mac (M1 or newer)." >&2; exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
  echo "Bucky requires macOS 14 or newer." >&2; exit 1
fi
xcrun --find swiftc >/dev/null || { echo "Install Apple's Command Line Tools: xcode-select --install" >&2; exit 1; }
if command -v uv >/dev/null 2>&1; then
  UV="$(command -v uv)"
elif [[ -x "$ROOT/.venv/bin/uv" ]]; then
  UV="$ROOT/.venv/bin/uv"
else
  echo "Install uv first (for example: brew install uv), then run this script again." >&2; exit 1
fi
# Runtime, dependencies and model downloads contain no recordings or history.
export UV_PYTHON_INSTALL_DIR="$ROOT/.runtime"
"$UV" python install 3.12.15
if [[ ! -x .venv/bin/python ]]; then
  "$UV" venv --python 3.12.15 .venv
fi
"$UV" pip install --python .venv/bin/python -r requirements.lock.txt
.venv/bin/python worker.py --download
.venv/bin/python - <<'VERIFY'
import hashlib
from pathlib import Path
path = Path('model/model.safetensors')
with path.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
if digest != '05e01c7f396c298cf7d23f61da7b504adeab698f0aaeafd9c82d198625464592':
    raise SystemExit('Model checksum mismatch; installation stopped before building the app.')
print('Pinned model checksum verified.')
VERIFY
bash scripts/build.sh
printf '\nInstalled. Open ~/Applications/Bucky.app and grant Microphone and Accessibility.\nKeep this source folder in place; rebuild after moving it.\n'
