"""Installer checks use temporary homes and local Git remotes, never live config."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def test_links_and_repeated_backups_preserve_user_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            personal = root / 'personal'
            shutil.copytree(ROOT / 'personal', personal)
            shutil.copytree(ROOT / 'assets', root / 'assets')
            config = root / 'config'
            commands = root / 'commands'
            commands.mkdir()
            stub = commands / 'hyprctl'
            stub.write_text('#!/bin/sh\nexit 1\n')
            stub.chmod(0o755)
            sudo = commands / 'sudo'
            sudo.write_text('#!/bin/sh\nexit 1\n')
            sudo.chmod(0o755)
            env = {**os.environ, 'HOME': str(root), 'XDG_CONFIG_HOME': str(config),
                   'PATH': f'{commands}:{root}/.local/bin:/usr/bin:/bin'}
            target = config / 'caelestia/shell.json'
            target.parent.mkdir(parents=True)
            target.write_text('first settings')
            for value in ('first settings', 'second settings'):
                if value == 'second settings':
                    self.assertEqual((root / '.face').read_bytes(), (ROOT / 'assets/user.svg').read_bytes())
                    (root / '.face').write_text('custom avatar')
                if target.is_symlink():
                    target.unlink()
                    target.write_text(value)
                subprocess.run(['bash', str(personal / 'install.sh')], env=env,
                               check=True, capture_output=True, text=True)
                self.assertTrue(target.is_symlink())
            self.assertEqual((root / '.face').read_text(), 'custom avatar')
            backups = {p.read_text() for p in target.parent.glob('shell.json.backup.*/original')}
            self.assertEqual(backups, {'first settings', 'second settings'})
            self.assertEqual((root / '.local/bin/rice-update').resolve(), personal / 'update.sh')
            for path in config.rglob('*'):
                if path.is_symlink():
                    self.assertTrue(path.exists(), str(path))

    def test_legacy_branch_migrates_and_tracks_main(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            remote, local = root / 'remote', root / 'local'
            def git(*args):
                return subprocess.run(['git', *map(str, args)], check=True, capture_output=True, text=True).stdout.strip()
            git('init', '-b', 'main', remote)
            git('-C', remote, 'config', 'user.name', 'Test')
            git('-C', remote, 'config', 'user.email', 'test@example.invalid')
            (remote / 'file').write_text('original')
            git('-C', remote, 'add', '.')
            git('-C', remote, 'commit', '-m', 'initial')
            git('clone', remote, local)
            git('-C', local, 'branch', '-m', 'mine')
            (remote / 'new').write_text('new main change')
            git('-C', remote, 'add', '.')
            git('-C', remote, 'commit', '-m', 'update')
            source = (ROOT / 'personal/bootstrap.sh').read_text()
            function = source.split('prepare_main() {', 1)[1].split('\n}\n', 1)[0]
            script = 'set -euo pipefail\nc_err() { echo "$*" >&2; }\nprepare_main() {' + function + '\n}\nprepare_main "$1"\n'
            subprocess.run(['bash', '-c', script, 'test', str(local)], check=True, capture_output=True, text=True)
            self.assertEqual(git('-C', local, 'branch', '--show-current'), 'main')
            self.assertEqual(git('-C', local, 'rev-parse', '--abbrev-ref', '@{upstream}'), 'origin/main')
            self.assertTrue((local / 'new').exists())

    def test_shell_syntax(self):
        for path in (ROOT / 'personal').glob('*.sh'):
            subprocess.run(['bash', '-n', str(path)], check=True)
