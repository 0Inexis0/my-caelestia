import importlib.util
import json
import os
import shutil
from pathlib import Path
import tempfile
import unittest
import io
import contextlib
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('manage', Path(__file__).resolve().parents[1] / 'personal/manage.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class OutputTests(unittest.TestCase):
    def test_ninja_progress_uses_completed_edges_and_rejects_invalid_counts(self):
        progress = [0, 0]
        m.parse_progress('warning\n[rice:143/223] compiler\n', progress)
        self.assertEqual(progress, [143, 223])
        m.parse_progress('[rice:1/0]\n[rice:9/2]', progress)
        self.assertEqual(progress, [143, 223])

    def test_compile_logs_errors_and_parses_progress(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'build.log'
            with patch.object(m, 'LOG', log), contextlib.redirect_stdout(io.StringIO()):
                with patch.object(m, 'parse_progress', wraps=m.parse_progress) as parser:
                    m.compile_command(sys.executable, '-c', 'print("[rice:1/2] first"); print("[rice:2/2] done")')
                    self.assertTrue(any('[rice:2/2]' in call.args[0] for call in parser.call_args_list))
                with self.assertRaises(m.subprocess.CalledProcessError) as error:
                    m.compile_command(sys.executable, '-c', 'import sys; print("fatal compiler error"); sys.exit(1)')
                self.assertIn('fatal compiler error', error.exception.stderr)

    def test_success_output_is_logged_and_capture_stays_parseable(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'update.log'
            with patch.object(m, 'LOG', log), contextlib.redirect_stdout(io.StringIO()) as visible:
                value = m.run(sys.executable, '-c', 'import sys; print("value"); print("warning", file=sys.stderr)', capture=True)
                m.run(sys.executable, '-c', 'print("build details")')
            self.assertEqual(value, 'value\n')
            self.assertEqual(visible.getvalue(), '')
            self.assertIn('warning', log.read_text())
            self.assertIn('build details', log.read_text())

    def test_failure_retains_diagnostics_and_marks_step_failed(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(m, 'LOG', Path(directory) / 'update.log'):
                with contextlib.redirect_stdout(io.StringIO()) as visible:
                    with self.assertRaises(m.subprocess.CalledProcessError) as error:
                        with m.step('Test build'):
                            m.run(sys.executable, '-c', 'import sys; print("compiler error", file=sys.stderr); sys.exit(2)')
                self.assertIn('compiler error', error.exception.stderr)
                self.assertIn('[✗] Test build', visible.getvalue())

    def test_interrupt_marks_step_failed_without_traceback(self):
        with patch.object(m, 'LOG', Path('/unused')):
            with contextlib.redirect_stdout(io.StringIO()) as visible:
                with self.assertRaises(KeyboardInterrupt):
                    with m.step('Interrupted'):
                        raise KeyboardInterrupt
            self.assertIn('[✗] Interrupted', visible.getvalue())


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data = self.root / 'data'
        self.data.mkdir()
        self.config = self.root / 'config/caelestia'
        self.config.parent.mkdir()
        self.old = self.release('old')
        self.new = self.release('new')
        self.config.symlink_to(self.old / 'shell')

    def release(self, name):
        path = self.data / name
        (path / 'shell').mkdir(parents=True)
        (path / 'shell/shell.qml').write_text(name)
        (path / 'qml').mkdir()
        (path / 'release.json').write_text(json.dumps({'revision': name}))
        return path

    def test_empty_instance_message_is_not_json(self):
        with patch.object(m, 'run', return_value='No running instances for "/config/shell.qml"\nUse --all to list all instances.\n'):
            self.assertEqual(m.instances(self.config), [])

    def test_reuse_requires_matching_inputs_and_intact_artifacts(self):
        fingerprint = {'revision': 'abc', 'qt': '6.12', 'dependencies': {'gcc': '16'}}
        (self.old / 'release.json').write_text(json.dumps({
            'fingerprint': fingerprint, 'artifacts': m.artifact_manifest(self.old)}))
        self.assertEqual(m.reusable_release(self.config, fingerprint), self.old)
        for changed in ({**fingerprint, 'revision': 'new'}, {**fingerprint, 'qt': '6.13'},
                        {**fingerprint, 'dependencies': {'gcc': '17'}}):
            self.assertIsNone(m.reusable_release(self.config, changed))
        (self.old / 'shell/shell.qml').write_text('corrupt')
        self.assertIsNone(m.reusable_release(self.config, fingerprint))

    def test_legacy_metadata_and_missing_artifacts_require_rebuild(self):
        self.assertIsNone(m.reusable_release(self.config, {'revision': 'old'}))
        (self.old / 'release.json').write_text('{broken json')
        self.assertIsNone(m.reusable_release(self.config, {}))

    def test_valid_instance_json(self):
        with patch.object(m, 'run', return_value='[{"pid": 123}]'):
            self.assertEqual(m.instances(self.config), [{'pid': 123}])

    def test_unknown_instance_output_fails_closed(self):
        with patch.object(m, 'run', return_value='unexpected CLI failure'):
            with self.assertRaises(RuntimeError):
                m.instances(self.config)

    def test_activation_switches_whole_release_and_preserves_previous(self):
        m.activate(self.new, self.config, self.data, restart=False)
        self.assertEqual(self.config.resolve(), self.new / 'shell')
        self.assertEqual((self.data / 'previous').resolve(), self.old / 'shell')
        self.assertEqual((self.old / 'shell/shell.qml').read_text(), 'old')

    def test_failed_launch_restores_previous_release(self):
        with patch.object(m, 'stop'), patch.object(m, 'start', side_effect=[RuntimeError('failed'), None]) as start:
            with self.assertRaises(RuntimeError):
                m.activate(self.new, self.config, self.data)
        self.assertEqual(self.config.resolve(), self.old / 'shell')
        self.assertEqual(start.call_count, 2)

    def test_stop_failure_never_changes_active_release(self):
        with patch.object(m, 'stop', side_effect=RuntimeError('still running')), patch.object(m, 'start') as start:
            with self.assertRaises(RuntimeError):
                m.activate(self.new, self.config, self.data)
        self.assertEqual(self.config.resolve(), self.old / 'shell')
        start.assert_called_once_with(self.config)

    def test_legacy_directory_is_restored_on_failure(self):
        self.config.unlink()
        self.config.mkdir()
        (self.config / 'shell.qml').write_text('legacy')
        with patch.object(m, 'stop'), patch.object(m, 'start', side_effect=[RuntimeError('failed'), None]):
            with self.assertRaises(RuntimeError):
                m.activate(self.new, self.config, self.data)
        self.assertFalse(self.config.is_symlink())
        self.assertEqual((self.config / 'shell.qml').read_text(), 'legacy')

    def test_failed_build_removes_only_incomplete_release(self):
        with patch.object(m, 'git', return_value='abc123'), patch.object(m, 'run', side_effect=RuntimeError('compiler failed')):
            with self.assertRaises(RuntimeError):
                m.build(self.root, self.data)
        self.assertEqual(list((self.data / 'releases').iterdir()), [])
        self.assertTrue((self.old / 'release.json').exists())
        self.assertEqual(self.config.resolve(), self.old / 'shell')


class RepairTests(unittest.TestCase):
    def test_healthy_quickshell_needs_no_build(self):
        with patch.object(m, 'quickshell_healthy', return_value=True), patch.object(m, 'compile_command') as build:
            self.assertFalse(m.ensure_quickshell(Path('/unused')))
            build.assert_not_called()

    def test_failed_build_never_removes_or_installs_provider(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(m, 'quickshell_healthy', return_value=False), patch.object(m, 'run') as run:
                with patch.object(m, 'compile_command', side_effect=RuntimeError('build failed')):
                    with self.assertRaises(RuntimeError):
                        m.ensure_quickshell(Path(directory))
                self.assertFalse(any('-U' in call.args or '-Rdd' in call.args for call in run.call_args_list))

    def test_repair_installs_only_exact_built_package_and_rechecks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / 'quickshell-git.pkg.tar.zst'
            package.touch()
            def command(*args, **kwargs):
                if args[:2] == ('makepkg', '--packagelist'):
                    return str(package) + '\n'
                if args[:2] in (('pacman', '-Qpq'), ('pacman', '-Qoq')):
                    return 'quickshell-git\n'
                return ''
            with patch.object(m, 'quickshell_healthy', side_effect=[False, True]) as check:
                with patch.object(m, 'run', side_effect=command) as run, patch.object(m, 'compile_command') as build:
                    self.assertTrue(m.ensure_quickshell(root))
                    self.assertEqual(check.call_count, 2)
                    self.assertIn('--cleanbuild', build.call_args.args)
                    installs = [call.args for call in run.call_args_list if '-U' in call.args]
                    self.assertEqual(installs, [('sudo', '-n', 'pacman', '-U', '--noconfirm', str(package))])

    def test_wrong_provider_fails_health_check_without_trusting_its_version(self):
        with patch.object(m, 'run', return_value='noctalia-qs\n') as run:
            self.assertFalse(m.quickshell_healthy())
            self.assertEqual(run.call_count, 1)

    def test_dependency_closure_ignores_unrelated_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def package(name, version, dependencies=''):
                path = root / name
                path.mkdir(exist_ok=True)
                (path / 'desc').write_text(f'%NAME%\n{name}\n\n%VERSION%\n{version}\n\n%DEPENDS%\n{dependencies}\n')
            package('gcc', '1', 'libc>=1')
            package('libc', '1')
            package('firefox', '1')
            first = m.dependency_state(root)
            package('firefox', '2')
            self.assertEqual(first, m.dependency_state(root))
            package('libc', '2')
            self.assertNotEqual(first, m.dependency_state(root))


class GitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source'
        self.data = self.root / 'data'
        self.data.mkdir()
        m.run('git', 'init', '-q', '-b', 'main', self.source)
        m.git(self.source, 'config', 'user.name', 'Test')
        m.git(self.source, 'config', 'user.email', 'test@example.invalid')
        self.commit('base.txt', 'base')
        self.base = m.git(self.source, 'rev-parse', 'HEAD')
        m.git(self.source, 'update-ref', 'refs/remotes/origin/main', self.base)
        m.git(self.source, 'update-ref', 'refs/remotes/upstream/main', self.base)

    def commit(self, name, text):
        (self.source / name).write_text(text)
        m.git(self.source, 'add', name)
        m.git(self.source, 'commit', '-qm', text)

    def test_candidate_merges_both_remotes_without_touching_source(self):
        self.commit('remote.txt', 'remote')
        remote = m.git(self.source, 'rev-parse', 'HEAD')
        m.git(self.source, 'update-ref', 'refs/remotes/origin/main', remote)
        m.git(self.source, 'checkout', '-q', '--detach', self.base)
        self.commit('upstream.txt', 'upstream')
        upstream = m.git(self.source, 'rev-parse', 'HEAD')
        m.git(self.source, 'update-ref', 'refs/remotes/upstream/main', upstream)
        m.git(self.source, 'checkout', '-q', '-B', 'main', self.base)
        self.commit('local.txt', 'local')
        local = m.git(self.source, 'rev-parse', 'HEAD')
        with m.candidate(self.source, self.data, True) as path:
            for ref in (local, remote, upstream):
                m.git(path, 'merge-base', '--is-ancestor', ref, 'HEAD')
            self.assertTrue((path / 'upstream.txt').exists())
        self.assertEqual(m.git(self.source, 'rev-parse', 'HEAD'), local)
        self.assertFalse((self.source / 'upstream.txt').exists())
        self.assertFalse(path.exists())

    def test_conflict_keeps_live_source_and_cleans_worktree(self):
        self.commit('base.txt', 'remote change')
        m.git(self.source, 'update-ref', 'refs/remotes/upstream/main', m.git(self.source, 'rev-parse', 'HEAD'))
        m.git(self.source, 'checkout', '-q', '-B', 'main', self.base)
        self.commit('base.txt', 'local change')
        head = m.git(self.source, 'rev-parse', 'HEAD')
        with self.assertRaises(RuntimeError):
            with m.candidate(self.source, self.data, True):
                self.fail('Conflicting candidate must not be activated')
        self.assertEqual(m.git(self.source, 'rev-parse', 'HEAD'), head)
        self.assertEqual(m.git(self.source, 'status', '--porcelain'), '')
        self.assertEqual(list(self.data.iterdir()), [])

    def test_autosave_failure_is_not_treated_as_clean(self):
        (self.source / 'edit.txt').write_text('keep me')
        hook = self.source / '.git/hooks/pre-commit'
        hook.write_text('#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        with self.assertRaises(m.subprocess.CalledProcessError):
            m.save_edits(self.source)
        self.assertEqual((self.source / 'edit.txt').read_text(), 'keep me')
        self.assertEqual(m.git(self.source, 'rev-parse', 'HEAD'), self.base)

    def test_legacy_git_move_repairs_linked_worktree(self):
        linked = self.root / 'linked'
        m.run('git', '-C', self.source, 'worktree', 'add', '--detach', linked)
        release = self.root / 'release'
        (release / 'shell').mkdir(parents=True)
        (release / 'shell/shell.qml').write_text('new')
        m.activate(release, self.source, self.data, restart=False)
        self.assertEqual(m.git(linked, 'rev-parse', 'HEAD'), self.base)
        self.assertTrue((self.data / 'previous/.git').is_dir())



@unittest.skipUnless(os.environ.get('CAELESTIA_QS_TESTS') == '1' and shutil.which('qs'),
                     'opt-in Quickshell runtime test')
class QuickshellTransactionTests(unittest.TestCase):
    def test_activation_and_rollback_restart_the_config_alias(self):
        with tempfile.TemporaryDirectory(prefix='caelestia-transaction-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            data = root / 'data/my-caelestia'
            config = root / 'config/quickshell/caelestia'
            config.parent.mkdir(parents=True)
            old, new = data / 'old', data / 'new'
            for release in (old, new):
                (release / 'shell').mkdir(parents=True)
                (release / 'shell/shell.qml').write_text(
                    'import Quickshell\nimport Quickshell.Io\n'
                    'ShellRoot { IpcHandler { target: "probe"; '
                    'function value(): string { return "' + release.name + '"; } } }\n')
            config.symlink_to(old / 'shell')
            env = dict(QT_QPA_PLATFORM='offscreen', WAYLAND_DISPLAY='',
                       XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_DATA_HOME=str(root / 'data'), XDG_CACHE_HOME=str(root / 'cache'),
                       XDG_STATE_HOME=str(root / 'state'))
            with patch.dict(os.environ, env):
                try:
                    m.start(config)
                    m.activate(new, config, data)
                    self.assertEqual(m.run('qs', '-p', config, 'ipc', 'call', 'probe', 'value', capture=True).strip(), 'new')
                    with patch.object(m.sys, 'argv', ['manage.py', 'rollback']):
                        m.main()
                    self.assertEqual(m.run('qs', '-p', config, 'ipc', 'call', 'probe', 'value', capture=True).strip(), 'old')
                    self.assertEqual(config.resolve(), old / 'shell')
                finally:
                    m.stop(config)

if __name__ == '__main__':
    unittest.main()
