"""Configuration safety checks; never allocate swap or invoke power actions."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('hibernate', ROOT / 'personal/hibernate.py')
hibernate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hibernate)
UUID = 'da22d6b0-755a-4222-8772-5c009e5f74b5'


class HibernateTests(unittest.TestCase):
    def test_limine_preserves_other_options_and_updates_only_managed_offset(self):
        original = 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]+="quiet rootflags=subvol=/@"\n'
        first = hibernate.resume_config(original, UUID, 1234)
        self.assertTrue(first.startswith(original))
        self.assertEqual(first, hibernate.resume_config(first, UUID, 1234))
        updated = hibernate.resume_config(first, UUID, 5678)
        self.assertTrue(updated.startswith(original))
        self.assertNotIn('resume_offset=1234', updated)
        self.assertEqual(updated.count('resume=UUID='), 1)
        self.assertIn('resume_offset=5678', updated)

    def test_existing_resume_settings_are_rejected(self):
        for option in ('resume=UUID=old', 'resume_offset=123', 'noresume'):
            with self.subTest(option=option), self.assertRaises(RuntimeError):
                hibernate.resume_config(f'KERNEL_CMDLINE[default]+=" {option}"\n', UUID, 1234)

    def test_invalid_resume_values_cannot_inject_shell_config(self):
        for uuid, offset in ((UUID + '"', 123), (UUID, '1$(touch /tmp/wrong)')):
            with self.subTest(uuid=uuid, offset=offset), self.assertRaises(RuntimeError):
                hibernate.resume_config('', uuid, offset)

    def test_fstab_keeps_zram_and_mounts_snapshot_independent_subvolume(self):
        original = '# existing mounts\n/dev/zram0 none swap pri=100 0 0\n'
        result = hibernate.fstab_config(original, UUID)
        self.assertTrue(result.startswith(original))
        self.assertIn('subvol=/@caelestia-swap,noatime', result)
        self.assertIn('/swap/caelestia.swap none swap defaults,pri=10', result)
        self.assertEqual(result, hibernate.fstab_config(result, UUID))

    def test_fstab_conflicts_and_broken_managed_blocks_are_rejected(self):
        for original in ('UUID=old /swap btrfs defaults 0 0\n',
                         '/swap/caelestia.swap none swap defaults 0 0\n',
                         hibernate.BEGIN + '\nincomplete\n'):
            with self.subTest(original=original), self.assertRaises(RuntimeError):
                hibernate.fstab_config(original, UUID)

    def test_atomic_config_write_retains_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config'
            path.write_text('original')
            path.chmod(0o640)
            hibernate.write_config(path, 'changed\n')
            self.assertEqual(path.read_text(), 'changed\n')
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_setup_refuses_unprivileged_execution_before_any_commands(self):
        with patch.object(hibernate.os, 'geteuid', return_value=1000), \
                patch.object(hibernate, 'run') as command:
            with self.assertRaisesRegex(RuntimeError, 'needs root'):
                hibernate.setup(36)
            command.assert_not_called()

    def test_setup_refuses_package_transaction_before_creating_anything(self):
        with patch.object(hibernate.os, 'geteuid', return_value=0), \
                patch.object(hibernate.Path, 'exists', return_value=True), \
                patch.object(hibernate.Path, 'open') as opened, \
                patch.object(hibernate, 'run') as command:
            with self.assertRaisesRegex(RuntimeError, 'package update is active'):
                hibernate.setup(36)
            opened.assert_not_called()
            command.assert_not_called()
