-- Class matches are RE2 regexes and unanchored, so always anchor them.
-- App ids are the ones niri reported (cfg/rules.kdl); (?i) covers the
-- X11-vs-Wayland casing differences (Slack vs slack, Spotify vs spotify).

-- Slack, Telegram and Spotify open on the tiled portrait screen without
-- stealing focus.
hl.window_rule({
    name = "comms",
    match = { class = [[(?i)^(slack|org\.telegram\.desktop|telegramdesktop|spotify)$]] },
    workspace = "7 silent",
})

-- Discord and Grok Bot share the 1080p screen, side by side.
hl.window_rule({
    name = "ambient",
    match = { class = [[(?i)^(discord|grok-bot)$]] },
    workspace = "8 silent",
})

-- Apps toggling their own maximize state would fight monocle; only the
-- layout decides window size.
hl.window_rule({
    name = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Upstream default: invisible XWayland drag helpers must not take focus.
hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

-- Wispr Flow's status overlay is a transparent XWayland window; blurring
-- behind it draws a dark frosted box over whatever is underneath. Wispr
-- marks it click-through with an X11 input shape, which Hyprland ignores,
-- so the whole box eats clicks wherever it sits. Keep it off-screen; the
-- start/stop sounds are enough feedback. It opens as "Flow Status
-- Indicator" and renames itself "Status".
hl.window_rule({
    name = "wispr-flow-status",
    match = { class = "^wispr-flow$", title = "^(Flow Status Indicator|Status)$" },
    no_blur = true,
    no_shadow = true,
    suppress_event = "x11configurerequest",
})

-- Wispr still moves it back to the bottom centre of the screen under the
-- pointer now and then, without any event Hyprland reports, so check every
-- second. The monitors span 0..3460 x 0..2520 in layout coordinates.
local WISPR_PARK_X = 5000
hl.timer(function()
    for _, w in ipairs(hl.get_windows()) do
        if w.class == "wispr-flow" and w.title == "Status" and w.at.x < WISPR_PARK_X then
            hl.dispatch(hl.dsp.window.move({
                window = "address:" .. w.address,
                x = WISPR_PARK_X,
                y = 0,
            }))
        end
    end
end, { timeout = 1000, type = "repeat" })

-- Noctalia, per its Hyprland guide: the settings window floats, and its
-- surfaces get blur but no Hyprland animations (it animates itself).
hl.window_rule({
    name = "noctalia-settings",
    match = { class = [[^dev\.noctalia\.Noctalia$]] },
    float = true,
    size = { 1080, 920 },
})

hl.layer_rule({
    name = "noctalia",
    match = {
        namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
    },
    no_anim = true,
    ignore_alpha = 0.5,
    blur = true,
    blur_popups = true,
})
