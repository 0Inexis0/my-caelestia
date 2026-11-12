"""Exercise monitor restarts with fake commands; never access the live shell."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'personal/config/hypr/scripts/restart-shell.sh'


class RestartShellTests(unittest.TestCase):
    def run_restart(self, *, restart_status=0, superseded=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / 'bin'
            commands.mkdir()
            runtime = root / 'runtime'
            runtime.mkdir()
            restore = root / '.config/caelestia/we-restore.sh'
            restore.parent.mkdir(parents=True)
            restore.write_text('printf "restore\\n" >> "$TEST_LOG"\n')
            stubs = {
                'caelestia': 'printf "caelestia %s\\n" "$*" >> "$TEST_LOG"\nexit "$TEST_RESTART_STATUS"\n',
                'sleep': 'if [ "$TEST_SUPERSEDED" = 1 ]; then printf newer > "$XDG_RUNTIME_DIR/caelestia-restart-stamp"; fi\n',
                'qs': 'printf "forbidden qs\\n" >> "$TEST_LOG"\nexit 99\n',
            }
            for name, body in stubs.items():
                path = commands / name
                path.write_text('#!/bin/bash\n' + body)
                path.chmod(0o755)
            log = root / 'calls.log'
            env = dict(os.environ, HOME=str(root), XDG_RUNTIME_DIR=str(runtime),
                       PATH=str(commands) + os.pathsep + os.defpath,
                       TEST_LOG=str(log), TEST_RESTART_STATUS=str(restart_status),
                       TEST_SUPERSEDED=str(int(superseded)))
            result = subprocess.run(['bash', str(SCRIPT)], env=env, capture_output=True, text=True)
            return result, log.read_text().splitlines() if log.exists() else []

    def test_native_restart_precedes_wallpaper_restore(self):
        result, calls = self.run_restart()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['caelestia shell -r -d', 'restore'])

    def test_failed_restart_does_not_restore_wallpaper(self):
        result, calls = self.run_restart(restart_status=7)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(calls, ['caelestia shell -r -d'])

    def test_superseded_monitor_event_does_not_restart(self):
        result, calls = self.run_restart(superseded=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [])
