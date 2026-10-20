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
local commands, rules, provider = {}, {}, nil
local workspace, special = {id = 4, name = "4", special = false}, nil
package.loaded.variables = {terminal = "foot --font='Monospace:size=12'"}
hl = {
    layout = {register = function(name, spec)
        assert(name == "caelestia-grid")
        provider = spec
    end},
    get_active_workspace = function() return workspace end,
    get_active_special_workspace = function() return special end,
    workspace_rule = function(rule) table.insert(rules, rule) end,
    exec_cmd = function(cmd, opts) table.insert(commands, {cmd, opts}) end,
}
local launcher = dofile(arg[1])
for count = 1, 20 do
    commands, rules = {}, {}
    launcher.launch(count)
    assert(#commands == count and #rules == 1)
    assert(rules[1].workspace == "4" and rules[1].layout == "lua:caelestia-grid")
    for _, command in ipairs(commands) do
        assert(command[1] == "foot --font='Monospace:size=12' fish -C codex")
        assert(command[2].workspace == "4")
    end
end
for _, bad in ipairs({0, -1, 21, 1.5, "3", "3;exit", math.huge}) do
    commands, rules = {}, {}
    assert(not pcall(launcher.launch, bad))
    assert(#commands == 0 and #rules == 0)
end
special = {id = -98, name = "special:communication", special = true}
commands, rules = {}, {}
launcher.launch(1)
assert(rules[1].workspace == "special:communication")
assert(commands[1][2].workspace == "special:communication")
special, workspace = nil, {id = -1337, name = "work", special = false}
launcher.launch(1)
assert(rules[#rules].workspace == "name:work")
workspace = nil
assert(not pcall(launcher.launch, 1))

for _, area in ipairs({
    {x=0,y=0,w=1920,h=1200}, {x=100,y=60,w=1200,h=1920},
    {x=-3840,y=0,w=3840,h=1080}, {x=20,y=20,w=1280,h=720},
}) do
    for count = 0, 20 do
        local boxes = {}
        local ctx = {area=area, targets={}}
        function ctx:grid_cell(i, columns, rows)
            return {x=area.x + ((i-1)%columns)*area.w/columns,
                y=area.y + math.floor((i-1)/columns)*area.h/rows,
                w=area.w/columns, h=area.h/rows}
        end
        for i = 1, count do
            ctx.targets[i] = {place=function(_, box) boxes[i] = box end}
        end
        provider.recalculate(ctx)
        assert(#boxes == count)
        for i, box in ipairs(boxes) do
            assert(box.w > 0 and box.h > 0)
            assert(box.x >= area.x and box.y >= area.y)
            assert(box.x + box.w <= area.x + area.w + .001)
            assert(box.y + box.h <= area.y + area.h + .001)
            assert(math.abs(box.w - boxes[1].w) < .001 and math.abs(box.h - boxes[1].h) < .001)
            for j = 1, i-1 do
                local b = boxes[j]
                assert(box.x >= b.x+b.w-.001 or b.x >= box.x+box.w-.001
                    or box.y >= b.y+b.h-.001 or b.y >= box.y+box.h-.001)
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
