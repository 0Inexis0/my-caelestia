"""Exercise layout changes and persistence without changing the live displays."""
import importlib.util
import json
from pathlib import Path
import tempfile
import shutil
import subprocess
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('displayctl', SOURCE / 'assets/displayctl.py')
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)


def monitor(name, **overrides):
    return dict(name=name, width=1920, height=1080, refreshRate=60,
                scale=1, disabled=False, mirrorOf='none', transform=0, **overrides)


class DisplayTests(unittest.TestCase):
    def test_fractional_scale_is_saved_precisely_after_confirmation(self):
        m = monitor('DP-2')
        for scale in (1.25, 1.75, 4/3):
            actual = {**m, 'scale': scale}
            with tempfile.TemporaryDirectory() as directory, patch.object(display.Path, 'home', return_value=Path(directory)), patch.object(display, 'hypr', return_value='ok') as ipc, patch.object(display, 'monitors', return_value=[actual]), patch.object(display.time, 'sleep'):
                display.apply(m, scale=scale)
                lua = ipc.call_args.args[1]
                self.assertIn(f'scale={scale}', lua)
                saved = (Path(directory) / '.config/hypr/monitors.d/DP-2.conf').read_text()
                self.assertAlmostEqual(float(saved.split(',')[2]), scale, places=6)

    def test_rejected_scale_does_not_overwrite_saved_configuration(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(display.Path, 'home', return_value=Path(directory)), patch.object(display, 'hypr', return_value='ok'), patch.object(display, 'monitors', return_value=[monitor('DP-2')]), patch.object(display.time, 'sleep'):
            target = Path(directory) / '.config/hypr/monitors.d/DP-2.conf'
            target.parent.mkdir(parents=True)
            target.write_text('old')
            with self.assertRaisesRegex(RuntimeError, 'not accepted'):
                display.apply(monitor('DP-2'), scale=1.25)
            self.assertEqual(target.read_text(), 'old')

    def test_mirror_and_extend_enable_source_first_and_ignore_virtual_outputs(self):
        panel, output = monitor('eDP-1'), monitor('DP-1')
        with tempfile.TemporaryDirectory() as directory, patch.object(display.Path, 'home', return_value=Path(directory)), patch.object(display, 'monitors', return_value=[panel, output, monitor('HEADLESS-2')]), patch.object(display, 'apply') as apply:
            display.layout('mirror')
            self.assertEqual(apply.call_args_list[0].args[0]['name'], 'eDP-1')
            self.assertEqual(apply.call_args_list[1].kwargs['mirror'], 'eDP-1')
            self.assertEqual(apply.call_count, 2)
            apply.reset_mock()
            display.layout('extend')
            self.assertTrue(all(call.kwargs['mirror'] == '' for call in apply.call_args_list))
            apply.reset_mock()
            display.layout('external')
            self.assertEqual(apply.call_args_list[0].args[0]['name'], 'DP-1')
            self.assertFalse(apply.call_args_list[1].kwargs['enabled'])

    def test_no_self_mirror_or_disabling_last_independent_output(self):
        m = monitor('eDP-1')
        with patch.object(display, 'monitors', return_value=[m]), patch.object(display, 'hypr') as ipc:
            with self.assertRaises(ValueError):
                display.apply(m, mirror='eDP-1')
            with self.assertRaises(ValueError):
                display.apply(m, enabled=False)
            ipc.assert_not_called()

    def test_cli_can_select_second_output(self):
        with patch.object(display, 'monitors', return_value=[monitor('eDP-1'), monitor('DP-1')]), patch.object(display, 'apply') as apply, patch('sys.argv', ['displayctl', json.dumps({'name': 'DP-1', 'scale': 1.25})]):
            display.main()
            self.assertEqual(apply.call_args.args[0]['name'], 'DP-1')
            self.assertEqual(apply.call_args.kwargs['scale'], 1.25)


    @unittest.skipUnless(shutil.which("lua"), "requires Lua")
    def test_reload_restores_legacy_and_mirror_configurations(self):
        with tempfile.TemporaryDirectory() as directory:
            configs = Path(directory) / '.config/hypr/monitors.d'
            configs.mkdir(parents=True)
            (configs / 'eDP-1.conf').write_text('2560x1600@60,auto,1.3333333333')
            (configs / 'DP-1.conf').write_text('1920x1080@60,auto,1,eDP-1')
            (configs / 'DP-2.conf').write_text('1920x1080@60,auto,1.25,')
            result = subprocess.run(['lua', '-', str(SOURCE / 'personal/config/hypr/hyprland/execs.lua'), directory], input='''
local getenv = os.getenv
os.getenv = function(key) if key == "HOME" then return arg[2] else return getenv(key) end end
package.loaded.variables = {}
package.loaded["hyprland.functions"] = {}
package.loaded["hyprland.codex"] = {}
local rules = {}
hl = {on=function() end, get_monitors=function() return {} end,
      monitor=function(rule) rules[rule.output] = rule end}
dofile(arg[1])
assert(rules["eDP-1"].mirror == "")
assert(math.abs(rules["eDP-1"].scale - 4/3) < 0.000001)
assert(rules["DP-1"].mirror == "eDP-1")
assert(rules["DP-2"].mirror == "" and rules["DP-2"].scale == 1.25)
''', text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
