{ lib, pkgs, ... }:

{
  # Noctalia is the shell for both Niri and Hyprland: bar, launcher,
  # notifications, lock, idle, polkit agent, and screenshots. Each compositor
  # starts it from its own config, so Plasma sessions never run it.
  home.packages = [ pkgs.noctalia ];

  # Keep a stable command in the first directory on the session PATH. This
  # also makes the v5 shell available to an already-running session before
  # the next system activation updates /etc/profiles/per-user.
  home.file.".local/bin/noctalia".source = lib.getExe pkgs.noctalia;

  # Keep the v5 bar edge-to-edge, matching the previous shell. The clock sits
  # in the status section in place of the network widget. Layout edits made in
  # Noctalia's settings land in ~/.local/state/noctalia/settings.toml and
  # override `end` here.
  xdg.configFile."noctalia/10-bar.toml".text = ''
    [bar.default]
    margin_ends = 0
    smart_auto_hide = true
    reserve_space = false
    center = []
    end = ["media", "ram", "vram", "tray", "notifications", "clipboard", "clock", "bluetooth", "volume", "brightness", "battery", "control-center", "session"]

    [bar.default.monitor.dell_27]
    match = "DP-2"
    smart_auto_hide = false
    reserve_space = true

    # Used VRAM in GiB, read through NVML (`gpu_vram` would be a percentage).
    [widget.vram]
    type = "sysmon"
    stat = "gpu_vram_used"
    glyph = "device-desktop"
  '';

  # The machine stays on overnight; the monitors shouldn't. Noctalia powers
  # every output off after 15 idle minutes and back on at the next input.
  # Idle inhibitors (video playback, the caffeine toggle) keep them on.
  xdg.configFile."noctalia/20-idle.toml".text = ''
    [idle.behavior.screen-off]
    timeout = 900
    action = "screen_off"
    enabled = true
  '';

  # Outside Plasma nothing else answers polkit prompts (1Password's system
  # unlock, NetworkManager, pkexec), so Noctalia's built-in agent does.
  xdg.configFile."noctalia/30-polkit.toml".text = ''
    [shell]
    polkit_agent = true
  '';

  # The Kanagawa Wave theme from T3 Code, shared with the terminals
  # (dots/.config/ghostty/themes/t3-kanagawa). Primary is T3's warm
  # highlight, hover and outline its #363646 surface. Picking another palette
  # in Noctalia's settings lands in ~/.local/state/noctalia/settings.toml and
  # overrides this.
  xdg.configFile."noctalia/palettes/T3-Kanagawa.json".text = ''
    {
      "dark": {
        "mPrimary": "#c8c093",
        "mOnPrimary": "#1f1f28",
        "mSecondary": "#7e9cd8",
        "mOnSecondary": "#1f1f28",
        "mTertiary": "#957fb8",
        "mOnTertiary": "#1f1f28",
        "mError": "#e46876",
        "mOnError": "#1f1f28",
        "mSurface": "#1f1f28",
        "mOnSurface": "#dcd7ba",
        "mSurfaceVariant": "#2a2a37",
        "mOnSurfaceVariant": "#95969b",
        "mOutline": "#363646",
        "mShadow": "#16161d",
        "mHover": "#363646",
        "mOnHover": "#edeef2",
        "terminal": {
          "normal": {
            "black": "#16161d",
            "red": "#c34043",
            "green": "#76946a",
            "yellow": "#c0a36e",
            "blue": "#7e9cd8",
            "magenta": "#957fb8",
            "cyan": "#6a9589",
            "white": "#c8c093"
          },
          "bright": {
            "black": "#727169",
            "red": "#e82424",
            "green": "#98bb6c",
            "yellow": "#e6c384",
            "blue": "#7fb4ca",
            "magenta": "#938aa9",
            "cyan": "#7aa89f",
            "white": "#dcd7ba"
          },
          "foreground": "#dcd7ba",
          "background": "#1f1f28",
          "selectionFg": "#dcd7ba",
          "selectionBg": "#223249",
          "cursorText": "#1f1f28",
          "cursor": "#dcd7ba"
        }
      }
    }
  '';
  xdg.configFile."noctalia/40-theme.toml".text = ''
    [theme]
    source = "custom"
    custom_palette = "T3-Kanagawa"
  '';
}
