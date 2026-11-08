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
    -- ASUS OSD: DCI-P3 gamut, 6500K; gamma 2.0 visually matches gamma 2.2.
    cm = "dp3",
    sdr_eotf = "gamma22",
    -- P3 at 8-bit bands in gradients.
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
