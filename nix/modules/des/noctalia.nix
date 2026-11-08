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
  # in the status section in place of the network widget.
  xdg.configFile."noctalia/10-bar.toml".text = ''
    [bar.default]
    margin_ends = 0
    smart_auto_hide = true
    reserve_space = false
    center = []
    end = ["media", "tray", "notifications", "clipboard", "clock", "bluetooth", "volume", "brightness", "battery", "control-center", "session"]

    [bar.default.monitor.dell_27]
    match = "DP-2"
    smart_auto_hide = false
    reserve_space = true
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
}
