"""Check the real Lua launcher and grid without touching the live compositor."""
from pathlib import Path
import shutil
import subprocess
import unittest

SOURCE = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("lua"), "requires Lua")
class CodexGridTests(unittest.TestCase):
    def test_launch_and_grid(self):
        result = subprocess.run(["lua", "-", str(SOURCE / "personal/config/hypr/hyprland/codex.lua")],
            input=r'''
local commands = {}
local monitor = {name="eDP-2", width=2560, height=1600, scale=4/3, transform=0,
    reserved={left=60, top=10, right=10, bottom=10}}
local workspace, special = {id=4, name="4", special=false, monitor=monitor}, nil
package.loaded.variables = {terminal = "foot --font='Monospace:size=12'"}
-- Any attempt to register layouts, alter workspace rules, or move other windows
-- fails: the launcher may only query its workspace and spawn its own processes.
hl = setmetatable({
    get_active_workspace = function() return workspace end,
    get_active_special_workspace = function() return special end,
    exec_cmd = function(cmd, opts) table.insert(commands, {cmd, opts}) end,
}, {__index=function(_, key) error("Forbidden compositor mutation: " .. key) end})
local launcher = dofile(arg[1])
for count = 1, 20 do
    commands = {}
    launcher.launch(count)
    assert(#commands == count)
    for _, command in ipairs(commands) do
        assert(command[1] == "foot --font='Monospace:size=12' fish -C codex")
        local opts = command[2]
        assert(opts.workspace == "4" and opts.monitor == "eDP-2")
        assert(opts.float == true and opts.center == nil)
        assert(opts.move:match("^%d+ %d+$") and opts.size:match("^%d+ %d+$"))
    end
end
for _, bad in ipairs({0, -1, 21, 1.5, "3", "3;exit", math.huge}) do
    commands = {}
    assert(not pcall(launcher.launch, bad))
    assert(#commands == 0)
end
special = {id=-98, name="special:communication", special=true, monitor=monitor}
commands = {}
launcher.launch(1)
assert(commands[1][2].workspace == "special:communication")
special, workspace = nil, {id=-1337, name="work", special=false, monitor=monitor}
launcher.launch(1)
assert(commands[#commands][2].workspace == "name:work")
commands, workspace = {}, nil
assert(not pcall(launcher.launch, 1) and #commands == 0)
workspace = {id=1}
assert(not pcall(launcher.launch, 1) and #commands == 0)

-- Non-overlapping, equal-size, monitor-local cells inside the scaled work area.
-- Negative global monitor positions must not offset monitor-local spawn rules.
for _, dimensions in ipairs({{1920,1200}, {2560,1600}, {3840,1080}, {1280,720}}) do
    for _, scale in ipairs({1, 4/3, 2}) do
        for transform = 0, 7 do
            monitor.width, monitor.height = dimensions[1], dimensions[2]
            monitor.scale, monitor.transform = scale, transform
            monitor.x, monitor.y = -3840, 60
            local width, height = monitor.width/scale, monitor.height/scale
            if transform % 2 == 1 then width, height = height, width end
            for count = 1, 20 do
                local boxes = launcher.grid(count, monitor)
                assert(#boxes == count)
                for i, box in ipairs(boxes) do
                    assert(box.w > 0 and box.h > 0)
                    assert(box.x >= 72 and box.y >= 22)
                    assert(box.x + box.w <= width - 22 + .001)
                    assert(box.y + box.h <= height - 22 + .001)
                    assert(box.w == boxes[1].w and box.h == boxes[1].h)
                    for j = 1, i-1 do
                        local b = boxes[j]
                        assert(box.x >= b.x+b.w or b.x >= box.x+box.w
                            or box.y >= b.y+b.h or b.y >= box.y+box.h)
                    end
                end
            end
        end
    end
end
print("Grid and interactive-fish launcher checks passed")
''', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Grid and interactive-fish launcher checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
