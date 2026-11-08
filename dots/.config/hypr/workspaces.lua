-- Workspaces are pinned to monitors and persistent, so Noctalia's indicator
-- always shows the full set. Numbers are what binds and rules target; the
-- names are only what the bar displays.

-- DP-1: one workspace per context, as on niri (Hyper+1..6).
local contexts = { "scratch", "Webroot", "UP", "Sealant", "Side", "Admin" }
for i, name in ipairs(contexts) do
    hl.workspace_rule({
        workspace = tostring(i),
        monitor = "DP-1",
        default = i == 1,
        default_name = name,
        persistent = true,
        layout = "monocle",
    })
end

-- HDMI-A-1: the tiled screen. Dwindle splits the portrait area top/bottom.
hl.workspace_rule({
    workspace = "7",
    monitor = "HDMI-A-1",
    default = true,
    default_name = "comms",
    persistent = true,
    layout = "dwindle",
    gaps_out = 4,
})

-- DP-2: Spotify and anything else parked on the small top screen.
hl.workspace_rule({
    workspace = "8",
    monitor = "DP-2",
    default = true,
    default_name = "ambient",
    persistent = true,
    layout = "monocle",
})
