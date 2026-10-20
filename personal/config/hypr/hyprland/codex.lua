local vars = require("variables")
local M = {}

-- Equal-sized tiles, independent of which window was focused when spawning.
-- Hyprland handles borders/gaps and reflows the grid as windows open or close.
function M.recalculate(ctx)
    local count = #ctx.targets
    if count == 0 then return end
    local aspect = ctx.area.w / math.max(1, ctx.area.h)
    local columns = math.min(count, math.max(1, math.ceil(math.sqrt(count * aspect / 1.6))))
    local rows = math.ceil(count / columns)
    for i, target in ipairs(ctx.targets) do
        target:place(ctx:grid_cell(i, columns, rows))
    end
end

hl.layout.register("caelestia-grid", { recalculate = M.recalculate })

function M.launch(count)
    assert(type(count) == "number" and count % 1 == 0 and count >= 1 and count <= 20,
        "Codex terminal count must be an integer from 1 to 20")
    local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
    assert(workspace, "No active workspace")
    local selector = tostring(workspace.id)
    if workspace.special then
        selector = "special:" .. workspace.name:gsub("^special:", "")
    elseif workspace.id < 0 then
        selector = "name:" .. workspace.name
    end
    hl.workspace_rule({ workspace = selector, layout = "lua:caelestia-grid" })
    for _ = 1, count do
        -- Same terminal and interactive fish startup as Super+T. -C runs Codex
        -- after fish's configuration and leaves a normal prompt when it exits.
        hl.exec_cmd(vars.terminal .. " fish -C codex", { workspace = selector })
    end
end

return M
