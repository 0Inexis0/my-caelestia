local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()
    -- Keyring and auth
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Clipboard history
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Auto delete trash 30 days old
    hl.exec_cmd("trash-empty 30")

    -- Cursors
    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    -- Location provider and night light
    hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")
    hl.exec_cmd("sleep 1 && gammastep")

    -- Forward bluetooth media commands to MPRIS
    hl.exec_cmd("mpris-proxy")

    -- Start shell
    hl.exec_cmd("caelestia shell -d")

    -- Re-launch Wallpaper Engine for the saved wallpaper. The wallpaper.postHook
    -- only fires on a wallpaper *change*, so a WE wallpaper isn't rendered at
    -- login until reselected; this restores it from path.txt.
    hl.exec_cmd("bash ~/.config/caelestia/we-restore.sh")
end)

-- Auto-disable internal display(s) when an external monitor is connected, and
-- re-enable them when the last external is unplugged. A display opts in when the
-- settings app creates ~/.config/hypr/.auto-disable-<name>. Uses hl.monitor()
-- (the legacy `hyprctl keyword monitor` does not work with the Lua parser).
local function is_internal(name)
    -- Type-guard: monitor events can hand us a table (no usable .name) or nil,
    -- and calling :match on a non-string throws "attempt to call a nil value".
    return type(name) == "string" and (name:match("^eDP") ~= nil or name:match("^LVDS") ~= nil)
end

-- Normalise a monitor event payload (table with .name, bare string, or nil) to
-- a plain name string or nil. Avoids the `a and a.name or a` pitfall, which
-- returns the table itself when .name is nil.
local function mon_name(mon)
    if type(mon) == "table" then
        return mon.name
    elseif type(mon) == "string" then
        return mon
    end
    return nil
end

local function marked_internals()
    local names = {}
    local p = io.popen("ls " .. os.getenv("HOME") .. "/.config/hypr/.auto-disable-* 2>/dev/null")
    if p then
        for line in p:lines() do
            local name = line:match("%.auto%-disable%-(.+)$")
            if name then
                names[#names + 1] = name
            end
        end
        p:close()
    end
    return names
end

local function has_external(exclude)
    for _, m in ipairs(hl.get_monitors()) do
        if not is_internal(m.name) and m.name ~= exclude then
            return true
        end
    end
    return false
end

-- Restart the shell (debounced) so the bar/panels re-draw on the current
-- monitors. Quickshell does not always re-create its per-monitor windows when a
-- monitor is added or removed.
local function restart_shell()
    hl.exec_cmd("bash ~/.config/hypr/scripts/restart-shell.sh")
end

hl.on("monitor.added", function(mon)
    local added = mon_name(mon)
    if not (added and is_internal(added)) then
        -- Only disable internals while an external is actually present (never black out everything)
        if has_external(nil) then
            for _, name in ipairs(marked_internals()) do
                hl.monitor({ output = name, disabled = true })
            end
        end
    end
    restart_shell()
end)

hl.on("monitor.removed", function(mon)
    local removed = mon_name(mon)
    if not has_external(removed) then
        for _, name in ipairs(marked_internals()) do
            hl.monitor({ output = name, disabled = false, mode = "preferred", position = "auto", scale = 1 })
        end
    end
    restart_shell()
end)

-- Restore per-monitor settings saved by the settings app on startup, so
-- resolution/refresh/scale survive a reboot. Each file
-- ~/.config/hypr/monitors.d/<name>.conf holds "mode,position,scale".
local function load_saved_monitors()
    local dir = os.getenv("HOME") .. "/.config/hypr/monitors.d"
    local p = io.popen("ls " .. dir .. "/*.conf 2>/dev/null")
    if not p then
        return
    end
    for path in p:lines() do
        local name = path:match("/([^/]+)%.conf$")
        local f = name and io.open(path, "r")
        if f then
            local spec = f:read("*l")
            f:close()
            local mode, pos, scale = (spec or ""):match("^([^,]+),([^,]+),([^,]+)$")
            if mode then
                pcall(function()
                    hl.monitor({ output = name, disabled = false, mode = mode, position = pos, scale = tonumber(scale) })
                end)
            end
        end
    end
    p:close()
end
load_saved_monitors()

-- Honor auto-disable for monitors already present at login or after a config
-- reload. The monitor.added events for startup monitors can fire before the
-- handler above is registered, and a reload re-runs the default monitor rule
-- (which would re-enable the internal), so re-evaluate on both events.
local function apply_auto_disable()
    if has_external(nil) then
        for _, name in ipairs(marked_internals()) do
            hl.monitor({ output = name, disabled = true })
        end
    end
end
hl.on("hyprland.start", apply_auto_disable)
hl.on("config.reloaded", apply_auto_disable)

-- Resizer listener
hl.on("window.title", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)

hl.on("window.open", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)
