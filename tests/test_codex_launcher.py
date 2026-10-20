"""Exercise launcher autocomplete, count validation and process arguments."""
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1]
RELEASE = Path(os.environ.get("CAELESTIA_TEST_RELEASE",
    str((Path.home() / ".config/quickshell/caelestia").resolve().parent)))
spec = importlib.util.spec_from_file_location("codex_launcher_manage", SOURCE / "personal/manage.py")
manage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manage)


@unittest.skipUnless(os.environ.get("CAELESTIA_QS_TESTS") == "1"
                     and (RELEASE / "release.json").exists()
                     and os.environ.get("WAYLAND_DISPLAY"),
                     "requires an installed plugin and opt-in graphical tests")
class CodexLauncherTests(unittest.TestCase):
    def test_launcher_interactions(self):
        with tempfile.TemporaryDirectory(prefix="codex-launcher-test-") as directory:
            staged = Path(directory)
            shutil.copytree(RELEASE / "shell", staged / "shell", symlinks=True)
            for name in ("components", "modules", "services", "utils"):
                shutil.copytree(SOURCE / name, staged / "shell" / name, dirs_exist_ok=True)
            shell = staged / "shell/shell.qml"
            text = shell.read_text()
            at = text.rfind("}")
            fixture = (SOURCE / "tests/fixtures/CodexLauncherChecks.qml").as_uri()
            shell.write_text(text[:at] + '\nLoader { active: false; Component.onCompleted: Qt.callLater(() => active = true); source: "' + fixture + '" }\n' + text[at:])
            log = staged / "test.log"
            try:
                # This fixture emits the readiness marker only after all interactions.
                with patch.object(manage, "add_feature_probe", return_value=None):
                    manage.smoke(staged, log)
            except RuntimeError:
                self.fail(log.read_text() if log.exists() else "No QML log produced")
            output = log.read_text()
            self.assertNotIn("Codex launcher interaction checks FAILED", output)
            self.assertIn("Codex launcher interaction checks passed", output)


if __name__ == "__main__":
    unittest.main()
