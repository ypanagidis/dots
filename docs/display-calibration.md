# Display calibration: DP-1 (ASUS ROG Strix XG27JCG)

The main monitor is calibrated in its own on-screen menu (OSD), not in software. Hyprland passes pixels straight through. Measured on 2026-11-13 with a Datacolor SpyderExpress and ArgyllCMS 3.5.0.

## OSD settings

Reset All first, then change only these:

| Setting | Value | Notes |
|---|---|---|
| GameVisual | Racing | factory default |
| Display Color Space | DCI-P3 | Wide Gamut is the factory default |
| Gamma | 2.0 | measures 2.12 |
| Contrast | 80 | factory; 252/255 stays distinct, so it doesn't clip |
| Color Temp | User, R94 G93 B91 | trimmed to D65 in DCI-P3 mode |
| Brightness | 78 | gives 251 cd/m², matching the MacBook Pro's 249 |
| VividPixel | 50 | neutral; 0 blurs |
| Variable OD | 0 | the factory 10 overshoots and leaves halos on dark UI |
| Overclocking | on | for 180 Hz; Reset All turns it off |

Everything else stays at factory: Shadow Boost, ELMB, Dynamic Dimming, ASCR and Blue Light Filter are all off.

## Measured result

| | Factory | Calibrated |
|---|---|---|
| White | 60 cd/m², 7190 K, bluish | 251 cd/m², 6475 K, neutral |
| Gamma | 2.34 | 2.12, flat |
| Contrast | 1063:1 | 940:1 |
| Accuracy as a P3 display | 3.0 ΔE avg | 1.1 ΔE avg |

The OSD labels are off on this panel:
- **Gamma:** "2.2" measures 2.34, "2.0" measures 2.12, and "1.8" measures 1.93.
- **Colour temperature:** the "6500K" preset measures about 7300 K.
- **RGB gains:** they apply differently in each colour space. The gains that give D65 in sRGB mode (R99 G97 B88) give 5880 K in DCI-P3 mode, so re-trim them after switching colour space.

## Hyprland side

`dots/.config/hypr/monitors.lua` sets DP-1 to `cm = "srgb"` with `sdr_eotf` at its default. `render.cm_sdr_eotf` in `hyprland.lua` also stays at its default. Source and output curves match, so Hyprland converts nothing. Apps' sRGB colours reach the P3 panel unmapped, so they look more saturated than intended, by about 3.6 ΔE. That's deliberate.

Rejected, after measuring and comparing by eye:
- **ICC profile:** Hyprland 0.57's ICC path clamps colours to sRGB. Its 33³ LUT is indexed in linear light, so everything below about 20% grey shares one cell and near-black gets crushed.
- **sRGB colour space:** it's accurate (1.1 ΔE), but it looks flat next to P3.
- **`sdr_eotf = "gamma22"`:** this adds the sRGB curve's lifted shadows (the Mac look). It made GitHub dark's background look grey; the panel's own ~2.1 curve looks better.
- **`cm = "dp3"`:** this maps sRGB into P3 correctly, and it looked worse by eye.

Hyprland 0.57 bug: `sdr_eotf` and `vrr` aren't compared when monitor rules are reloaded. Changing only those and reloading does nothing. Change `cm` too (for example to `dp3` and back, with two reloads) to force the rule to apply.

## Re-checking

The tools are in `~/.local/share/icc/xg27jcg-study/` (outside the repo), with all ten runs and their OSD settings in `runs/`.

1. Plug in the Spyder; `spotread -?` should list "Datacolor Spyder 2024".
2. Hang the sensor in the centre of DP-1. A rule in `rules.lua` pins Argyll's test window there.
3. Make sure Hyprland is in pass-through, which is the normal config.
4. Measure and compare against the final run:
   ```sh
   ~/.local/share/icc/xg27jcg-study/measure.sh recheck "notes"
   python3 -I ~/.local/share/icc/xg27jcg-study/analyze.py 10-p3-d65-final recheck
   ```
   Each measurement takes about a minute.
5. If white has drifted, re-trim the User gains while watching live readings:
   ```sh
   dispcal -v -d1 -yb -t6500 -b250 -P0.5,0.5,2 adjust
   ```
   In its menu, choose 2, then 3, then 8 to exit. Never choose 7: on Wayland it can't apply the curves it would create.

The system side lives in the Nix config:
- `nix/modules/media/default.nix` overrides ArgyllCMS to 3.5.0, because 3.4.1 reads this sensor as XYZ 1,1,1.
- `nix/configuration.nix` adds a udev rule so the sensor works without root.
