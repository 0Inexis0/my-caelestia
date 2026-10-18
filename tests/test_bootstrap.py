"""Bootstrap safety and final checks, with isolated paths and mocked commands."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / 'personal/bootstrap.sh').read_text()
spec = importlib.util.spec_from_file_location('verify_install', ROOT / 'personal/verify-install.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def function(name):
    return name + '() {' + SCRIPT.split(name + '() {', 1)[1].split('\n}\n', 1)[0] + '\n}\n'


class BootstrapTests(unittest.TestCase):
    def test_preview_and_decline_do_not_create_data(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory) / 'absent'
            for settings in ('DRY_RUN=1; ASSUME_YES=0; INTERACTIVE=0',
                             'DRY_RUN=0; ASSUME_YES=0; INTERACTIVE=1'):
                script = ('set -eu\nc_info(){ echo "$*"; }; c_ok(){ echo "$*"; }; c_err(){ echo "$*"; }; ask(){ return 1; };\n'
                          + settings + '\nDATA="$1"\n' + function('confirm_plan') + '\nconfirm_plan\nexit 99')
                result = subprocess.run(['bash', '-c', script, 'test', str(data)], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(data.exists())

    def test_step_hides_success_and_shows_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'install.log'
            script = ('set -eu\nc_ok(){ echo "$*"; }; c_err(){ echo "$*"; };\n'
                      'INSTALL_LOG="$1"; FRAMES="abcd"\n' + function('run_step') +
                      '\nrun_step success bash -c "echo hidden-detail"\n'
                      'run_step failure bash -c "echo visible-error >&2; exit 7"')
            result = subprocess.run(['bash', '-c', script, 'test', str(log)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 7)
            self.assertNotIn('hidden-detail', result.stdout + result.stderr)
            self.assertIn('visible-error', result.stderr)
            self.assertIn('hidden-detail', log.read_text())

    def test_preflight_rejects_insufficient_disk_without_network(self):
        script = ('set -eu\nDATA=/tmp; CFG=/tmp; LEGACY=/tmp; URL=unused\n'
                  'c_err(){ echo "$*"; }; c_warn(){ :; }; c_ok(){ :; }; have(){ return 0; };\n'
                  'df(){ printf "Filesystem blocks used available capacity mount\\nx 100 99 1 99%% /\\n"; };\n'
                  'timeout(){ echo unexpected-network; return 99; };\n' + function('preflight').replace('. /etc/os-release', 'ID=arch; ID_LIKE=arch') + '\npreflight')
        result = subprocess.run(['bash', '-c', script], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('unexpected-network', result.stdout)
        self.assertIn('12 GiB', result.stdout)

    def test_verifier_accepts_install_then_detects_damage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, config, data, bin_dir = (root / name for name in ('source', 'config', 'data', 'bin'))
            original = source / 'personal/config/hypr/hyprland.lua'
            original.parent.mkdir(parents=True)
            original.write_text('-- config')
            (config / 'hypr').mkdir(parents=True)
            link = config / 'hypr/hyprland.lua'
            link.symlink_to(original)
            (config / 'caelestia').mkdir()
            for name in ('shell.json', 'cli.json'):
                (config / 'caelestia' / name).write_text('{}')
            update = source / 'personal/update.sh'
            update.write_text('#!/bin/sh\n')
            update.chmod(0o755)
            bin_dir.mkdir()
            (bin_dir / 'rice-update').symlink_to(update)
            release = data / 'releases/test'
            (release / 'shell').mkdir(parents=True)
            (release / 'shell/shell.qml').write_text('ShellRoot {}')
            libs = release / 'qml/Caelestia/lib'
            libs.mkdir(parents=True)
            for name in ('core', 'components', 'config', 'services'):
                (libs / f'libcaelestia-{name}.so').touch()
            (release / 'release.json').write_text(json.dumps({'revision': 'abc', 'qt': '6.12'}))
            (config / 'quickshell').mkdir()
            (config / 'quickshell/caelestia').symlink_to(release / 'shell')
            with patch.object(verifier.subprocess, 'run') as run:
                verifier.verify(source, config, data, bin_dir, session=False)
                self.assertEqual(run.call_count, 1)
                verifier.verify(source, config, data, bin_dir, session=True)
                self.assertEqual(run.call_args.args[0][-2:], ['ipc', 'show'])
                link.unlink()
                (libs / 'libcaelestia-core.so').unlink()
                with self.assertRaisesRegex(RuntimeError, 'Config link.*\nCompiled plugin missing: core'):
                    verifier.verify(source, config, data, bin_dir, session=False)
