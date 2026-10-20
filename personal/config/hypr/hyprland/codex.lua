local vars = require("variables")
local M = {}

-- Arrange only this launch batch. Floating spawn rules leave the workspace's
-- tiled layout and every existing window untouched; no persistent rules/hooks.
function M.grid(count, monitor)
    local width, height = monitor.width / monitor.scale, monitor.height / monitor.scale
    if monitor.transform % 2 == 1 then width, height = height, width end
    local reserved = monitor.reserved
    local margin, gap = 12, 12
    local x, y = reserved.left + margin, reserved.top + margin
    width = width - reserved.left - reserved.right - 2 * margin
    height = height - reserved.top - reserved.bottom - 2 * margin
    assert(width > 0 and height > 0, "No usable monitor area")
    local columns = math.min(count, math.max(1, math.ceil(math.sqrt(count * width / height / 1.6))))
    local rows = math.ceil(count / columns)
    local w = math.floor((width - (columns - 1) * gap) / columns)
    local h = math.floor((height - (rows - 1) * gap) / rows)
    assert(w > 0 and h > 0, "Not enough space for Codex grid")
    local boxes = {}
    for i = 1, count do
        boxes[i] = { x = math.floor(x + ((i - 1) % columns) * (w + gap)),
            y = math.floor(y + math.floor((i - 1) / columns) * (h + gap)), w = w, h = h }
    end
    return boxes
end

function M.launch(count)
    assert(type(count) == "number" and count % 1 == 0 and count >= 1 and count <= 20,
        "Codex terminal count must be an integer from 1 to 20")
    local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
    assert(workspace, "No active workspace")
    local monitor = workspace.monitor
    assert(monitor, "No monitor for active workspace")
    local selector = tostring(workspace.id)
    if workspace.special then
        selector = "special:" .. workspace.name:gsub("^special:", "")
    elseif workspace.id < 0 then
        selector = "name:" .. workspace.name
    end
    for _, box in ipairs(M.grid(count, monitor)) do
        -- Same terminal and interactive fish startup as Super+T. -C runs Codex
        -- after fish's configuration and leaves a normal prompt when it exits.
        hl.exec_cmd(vars.terminal .. " fish -C codex", {
            workspace = selector, monitor = monitor.name, float = true,
            size = box.w .. " " .. box.h, move = box.x .. " " .. box.y,
        })
    end
end

return M
