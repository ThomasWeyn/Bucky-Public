"""Verify build protection without compiling or touching the installed Bucky."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='bucky-build-guard-') as directory:
    root = Path(directory)
    app = root / 'Existing Bucky.app'
    executable = app / 'Contents/MacOS/Bucky'
    executable.parent.mkdir(parents=True)
    executable.write_bytes(b'keep existing binary')
    before = sorted(str(p.relative_to(app)) for p in app.rglob('*'))
    # The stub prevents compilation even if the guard regresses.
    bindir = root / 'bin'
    bindir.mkdir()
    compiler = bindir / 'xcrun'
    compiler.write_text('#!/bin/sh\nexit 99\n')
    compiler.chmod(0o700)
    env = {**os.environ, 'BUCKY_APP_PATH': str(app), 'BUCKY_REPLACE_APP': '0',
           'PATH': str(bindir) + os.pathsep + os.environ['PATH']}
    result = subprocess.run(['bash', str(ROOT / 'scripts/build.sh')],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 2, 'Existing app was not protected'
    assert 'Refusing to replace' in result.stderr
    assert executable.read_bytes() == b'keep existing binary'
    assert sorted(str(p.relative_to(app)) for p in app.rglob('*')) == before
    # Explicit replacement reaches the compiler; the stub stops before re-signing.
    env['BUCKY_REPLACE_APP'] = '1'
    result = subprocess.run(['bash', str(ROOT / 'scripts/build.sh')],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 99, 'Explicit replacement route was not available'
    assert executable.read_bytes() == b'keep existing binary'
print('PASS: existing app protected before writes; deliberate replacement is explicit')
