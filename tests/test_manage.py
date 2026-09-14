import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('manage', Path(__file__).resolve().parents[1] / 'personal/manage.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


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
        with patch.object(m, 'stop', side_effect=RuntimeError('still running')):
            with self.assertRaises(RuntimeError):
                m.activate(self.new, self.config, self.data)
        self.assertEqual(self.config.resolve(), self.old / 'shell')

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


class GitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source'
        self.data = self.root / 'data'
        self.data.mkdir()
        m.run('git', 'init', '-q', '-b', 'mine', self.source)
        m.git(self.source, 'config', 'user.name', 'Test')
        m.git(self.source, 'config', 'user.email', 'test@example.invalid')
        self.commit('base.txt', 'base')
        self.base = m.git(self.source, 'rev-parse', 'HEAD')
        m.git(self.source, 'update-ref', 'refs/remotes/origin/mine', self.base)
        m.git(self.source, 'update-ref', 'refs/remotes/upstream/main', self.base)

    def commit(self, name, text):
        (self.source / name).write_text(text)
        m.git(self.source, 'add', name)
        m.git(self.source, 'commit', '-qm', text)

    def test_candidate_merges_both_remotes_without_touching_source(self):
        self.commit('remote.txt', 'remote')
        remote = m.git(self.source, 'rev-parse', 'HEAD')
        m.git(self.source, 'update-ref', 'refs/remotes/origin/mine', remote)
        m.git(self.source, 'checkout', '-q', '--detach', self.base)
        self.commit('upstream.txt', 'upstream')
        upstream = m.git(self.source, 'rev-parse', 'HEAD')
        m.git(self.source, 'update-ref', 'refs/remotes/upstream/main', upstream)
        m.git(self.source, 'checkout', '-q', '-B', 'mine', self.base)
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
        m.git(self.source, 'checkout', '-q', '-B', 'mine', self.base)
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


if __name__ == '__main__':
    unittest.main()
