-- Class matches are RE2 regexes and unanchored, so always anchor them.
-- App ids are the ones niri reported (cfg/rules.kdl); (?i) covers the
-- X11-vs-Wayland casing differences (Slack vs slack, Spotify vs spotify).

-- Comms apps open on the tiled portrait screen without stealing focus.
hl.window_rule({
    name = "comms",
    match = { class = [[(?i)^(slack|discord|org\.telegram\.desktop|telegramdesktop)$]] },
    workspace = "7 silent",
})

hl.window_rule({
    name = "spotify",
    match = { class = [[(?i)^spotify$]] },
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
