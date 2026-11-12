-- Same arrangement as niri's cfg/display.kdl. Positions are logical pixels:
-- DP-1 is 2560x1440 after scale 2, DP-2 sits centred above it, and the
-- portrait HDMI-A-1 is 900x2150 after rotation and scale 1.6, to the right,
-- bottom-aligned with DP-1.
-- Transform 2 = 180°, 3 = 270°.
hl.monitor({
    output = "DP-1",
    mode = "5120x2880@180.003",
    position = "0x1080",
    scale = 2,
    -- Calibrated in the monitor, not in Hyprland (SpyderExpress + ArgyllCMS
    -- 3.5.0, 2026-11-13; data in ~/.local/share/icc/xg27jcg-study/runs).
    -- ASUS OSD: Racing, Display Color Space DCI-P3, Gamma 2.0, Contrast 80,
    -- Color Temp User R94 G93 B91, Brightness 78, VividPixel 50 (neutral:
    -- 0 blurs), Variable OD 0 (factory 10 overshoots: halos on dark UI),
    -- Overclocking on (180Hz), everything else factory.
    -- Measured: white 251 cd/m2 (matches the MacBook Pro), 6475K, tint ~0;
    -- gamma 2.12 flat; greys neutral; 940:1; avg 1.1 dE as a P3 display.
    -- OSD labels run dark: "2.2" measures 2.34, "2.0" 2.12, "1.8" 1.93, and
    -- the "6500K" preset is ~7300K. User gains differ per colour space (the
    -- sRGB-mode trim R99 G97 B88 gives 5880K in P3 mode).
    -- Hyprland is a pure pass-through here (cm srgb, sdr_eotf and the global
    -- cm_sdr_eotf at default), so sRGB content shows with P3 saturation. That
    -- vivid look is the user's choice; so is the panel's ~2.1 curve over the
    -- sRGB toe (sdr_eotf = "gamma22" adds it; measured, user preferred
    -- without). No ICC: Hyprland 0.57's ICC path clamps to sRGB and crushes
    -- near-black (33^3 LUT indexed in linear light).
    -- Hyprland bug: sdr_eotf and vrr aren't in CMonitorRule::compare, so changing
    -- only those and reloading does nothing; flip `cm` too to force a reapply.
    cm = "srgb",
    -- Wide gamut at 8-bit bands in gradients.
    bitdepth = 10,
    vrr = 1,
})

hl.monitor({
    output = "DP-2",
    mode = "1920x1080@60",
    position = "320x0",
    scale = 1,
    transform = 2,
})

hl.monitor({
    output = "HDMI-A-1",
    mode = "3440x1440@59.973",
    position = "2560x370",
    -- Hyprland only accepts scales that give a whole-pixel logical size, and
    -- 3440/1.5 isn't one; it silently rounds 1.5 up to 1.6 anyway.
    scale = 1.6,
    transform = 3,
})

-- Anything else that gets plugged in.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "auto",
})
