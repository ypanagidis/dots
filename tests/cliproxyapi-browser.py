"""Check both OAuth browser launch paths without opening a browser or signing in.

Run: python tests/cliproxyapi-browser.py /path/to/cli-proxy-api
"""

import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

if len(sys.argv) != 2:
    raise SystemExit(__doc__)

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='cliproxyapi-browser-probe-') as temp:
    root = Path(temp)
    opener = root / 'xdg-open'
    shell = shutil.which('bash')
    if shell is None:
        raise SystemExit('This test requires bash.')
    opener.write_text(
        f'#!{shell}\n'
        'case "$1" in\n'
        '  about:blank) echo blank ;;\n'
        '  https://*) echo oauth ;;\n'
        '  *) echo unexpected ;;\n'
        'esac >> "$PROBE_LOG"\n'
    )
    opener.chmod(0o755)
    config = root / 'config.yaml'
    config.write_text('config-version: 8\nserver:\n  host: 127.0.0.1\noauth:\n  auth-dir: ' + str(root / 'auth') + '\n')
    env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', PROBE_LOG=str(root / 'opened'))
    for provider in ('codex', 'claude'):
        (root / 'opened').unlink(missing_ok=True)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        with (root / 'login.log').open('w') as log:
            process = subprocess.Popen([binary, '-config', str(config), f'-{provider}-login', '-oauth-callback-port', str(port)],
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=log, env=env, cwd=root)
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    markers = (root / 'opened').read_text().splitlines() if (root / 'opened').exists() else []
                    if 'oauth' in markers or process.poll() is not None:
                        break
                    time.sleep(0.1)
                print(f'{provider}: opened URL types = {markers}', flush=True)
                assert markers == ['oauth'], f'{provider}: expected only the login URL, got {markers}'
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    print('PASS: both OAuth logins open only their authorization URL, with no about:blank probe.')
