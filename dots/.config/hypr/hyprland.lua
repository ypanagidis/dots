-- Hyprland entry point. Lua-only since 0.57; the stubs for LuaLS live in
-- /run/current-system/sw/share/hypr/stubs (see .luarc.json).
--
-- Model: DP-1 and DP-2 run monocle, so every window fills the screen and
-- shortcuts switch between them. HDMI-A-1 (portrait) is the one tiled screen
-- and hosts the comms apps. Noctalia provides the bar, launcher,
-- notifications, lock, idle, polkit agent, and screenshots.

require("monitors")
require("workspaces")
require("rules")
require("binds")

-- Session environment lives in ~/.config/uwsm/env-hyprland (des/hyprland.nix):
-- hl.env only reaches Hyprland's own children, not the systemd units UWSM
-- starts apps and portals in.

hl.config({
    general = {
        layout = "monocle",
        gaps_in = 4,
        gaps_out = 0,
        border_size = 2,
        col = {
            active_border = "rgba(7aa2f7ee)",
            inactive_border = "rgba(00000000)",
        },
    },

    decoration = {
        rounding = 0,
        shadow = { enabled = false },
        blur = {
            enabled = true,
            size = 3,
            passes = 2,
            vibrancy = 0.1696,
        },
    },

    dwindle = {
        preserve_split = true,
    },

    input = {
        kb_layout = "us",
        repeat_delay = 275,
        repeat_rate = 45,
        numlock_by_default = true,
        follow_mouse = 1,
        natural_scroll = true,
        touchpad = { natural_scroll = true },
    },

    binds = {
        -- Pressing the shortcut for the workspace you're on goes back to the
        -- previous one, like niri's workspace-auto-back-and-forth.
        workspace_back_and_forth = true,
    },

    cursor = {
        -- Don't jump the pointer to the newly focused window on every
        -- shortcut; it stays where the mouse left it.
        no_warps = true,
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        -- Apps asking for focus (links opening in Helium, etc.) get it.
        focus_on_activate = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -- noctalia")
    -- The KWallet autostart entry is marked X-systemd-skip, so UWSM's XDG
    -- autostart never runs it. Without it the wallet SDDM unlocked via PAM
    -- stays locked for this session.
    hl.exec_cmd("/run/current-system/sw/libexec/pam_kwallet_init")
end)
