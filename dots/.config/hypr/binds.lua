local mod = "SUPER"
local hyper = "CTRL + ALT + SHIFT + SUPER"
local noctalia = "noctalia msg "

-- Launch through UWSM so every app gets its own systemd scope instead of
-- living (and dying) inside Hyprland's unit.
local function launch(desktop_id)
    hl.exec_cmd("uwsm app -- " .. desktop_id .. ".desktop")
end

-- Mapped windows whose class is in `classes` (a set of lowercased classes).
local function windows_of(classes)
    local found = {}
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and classes[w.class:lower()] then
            table.insert(found, w)
        end
    end
    return found
end

local function set(list)
    local s = {}
    for _, v in ipairs(list) do
        s[v:lower()] = true
    end
    return s
end

-- Focus the app's window, or launch it if it has none. Pressing again while
-- one of its windows is focused moves on to the next one, wrapping. Same
-- behaviour as `kde-apps focus` on Plasma.
local function focus_or_launch(classes, desktop_id)
    classes = set(classes)
    return function()
        local wins = windows_of(classes)
        if #wins == 0 then
            launch(desktop_id)
            return
        end
        local active = hl.get_active_window()
        local target = wins[1]
        for i, w in ipairs(wins) do
            if active and w.address == active.address then
                target = wins[i % #wins + 1]
                break
            end
        end
        hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
    end
end

-- Hyper+<letter> apps, matching the Plasma task-manager pins and hotkeys.
local apps = {
    A = { { "helium" }, "helium" },
    C = { { "com.mitchellh.ghostty" }, "com.mitchellh.ghostty" },
    D = { { "discord" }, "discord" },
    T = { { "spotify" }, "spotify" },
    O = { { "obsidian" }, "obsidian" },
    P = { { "jetbrains-datagrip" }, "datagrip" },
    M = { { "bruno" }, "bruno" },
    F = { { "com.t3tools.t3code" }, "t3-code" },
    S = { { "slack" }, "slack" },
}
for key, app in pairs(apps) do
    hl.bind(hyper .. " + " .. key, focus_or_launch(app[1], app[2]))
end

-- Hyper+V: open whichever comms app is missing (the comms rule sends it to
-- HDMI-A-1), then jump to that workspace.
local comms = {
    { { "slack" }, "slack" },
    { { "org.telegram.desktop", "telegramdesktop" }, "org.telegram.desktop" },
    { { "discord" }, "discord" },
}
hl.bind(hyper .. " + V", function()
    for _, app in ipairs(comms) do
        if #windows_of(set(app[1])) == 0 then
            launch(app[2])
        end
    end
    hl.dispatch(hl.dsp.focus({ workspace = "7" }))
end)

-- Shell (Noctalia).
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(noctalia .. "panel-toggle launcher"))
hl.bind(mod .. " + V", hl.dsp.exec_cmd(noctalia .. "panel-toggle clipboard"))
hl.bind(mod .. " + S", hl.dsp.exec_cmd(noctalia .. "panel-toggle control-center"))
hl.bind(mod .. " + comma", hl.dsp.exec_cmd(noctalia .. "settings-toggle"))
hl.bind(mod .. " + ALT + L", hl.dsp.exec_cmd(noctalia .. "session lock"))
hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd(noctalia .. "panel-toggle session"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd(noctalia .. "screenshot-region"))
hl.bind("Print", hl.dsp.exec_cmd(noctalia .. "screenshot-fullscreen pick"))
hl.bind("ALT + Tab", hl.dsp.exec_cmd(noctalia .. "window-switcher hold"))

hl.bind(mod .. " + Return", hl.dsp.exec_cmd("uwsm app -- com.mitchellh.ghostty.desktop"))

-- Windows. Tab cycles the windows stacked on the current workspace, which on
-- a monocle screen is how you switch between fullscreen apps.
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + Tab", hl.dsp.window.cycle_next({ tiled = true }))
hl.bind(mod .. " + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false, tiled = true }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.float())

-- Direction keys: focus moves within a tiled screen, and across monitors
-- when there's nothing further in that direction.
local directions = {
    H = "left", Left = "left",
    L = "right", Right = "right",
    K = "up", Up = "up",
    J = "down", Down = "down",
}
for key, dir in pairs(directions) do
    hl.bind(hyper .. " + " .. key, hl.dsp.focus({ direction = dir }))
    hl.bind(mod .. " + CTRL + " .. key, hl.dsp.window.swap({ direction = dir }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ monitor = dir }))
end

-- Workspaces: Hyper+N goes to context N on DP-1, Super+Ctrl+N sends the
-- focused window there without following it.
for i = 1, 6 do
    hl.bind(hyper .. " + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind(mod .. " + CTRL + " .. i, hl.dsp.window.move({ workspace = tostring(i), follow = false }))
end

-- Mouse: Super+drag moves, Super+right-drag resizes.
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media and volume keys, routed through Noctalia so its OSD shows.
local media = {
    XF86AudioRaiseVolume = "volume-up",
    XF86AudioLowerVolume = "volume-down",
    XF86AudioMute = "volume-mute",
    XF86AudioMicMute = "mic-mute",
    XF86AudioPlay = "media toggle",
    XF86AudioPause = "media toggle",
    XF86AudioNext = "media next",
    XF86AudioPrev = "media previous",
}
for key, cmd in pairs(media) do
    hl.bind(key, hl.dsp.exec_cmd(noctalia .. cmd), { locked = true, repeating = cmd:find("volume") ~= nil })
end
