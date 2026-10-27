{ pkgs, ... }:

{
  # System side of the graphical desktop: display server, login manager,
  # keyboard remapping, audio service, portals, and fonts.
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.displayManager.sddm.enable = true;

  # SDDM's greeter runs on KWin, which reads the monitor layout from the sddm
  # user's kwinoutputconfig.json. Without one, every screen comes up unrotated
  # at a guessed position. This copy mirrors niri's display.kdl, with DP-1 as
  # the primary so the login box lands there. KWin may replace the symlink
  # with its own copy; tmpfiles restores it on every boot.
  systemd.tmpfiles.rules = [
    "d /var/lib/sddm/.config 0755 sddm sddm -"
    "L+ /var/lib/sddm/.config/kwinoutputconfig.json - - - - ${./sddm-kwinoutputconfig.json}"
  ];
  services.desktopManager.plasma6.enable = true;

  # KDE's portal is needed by sandboxed/desktop apps for file pickers, screen
  # capture, and other desktop integrations.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  # Host-wide key remapping so it also applies before Home Manager services are
  # fully up and across all graphical apps.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [
        "*"
      ];
      settings = {
        main = {
          leftalt = "layer(alt_nav)";
          rightalt = "layer(alt_nav)";
          leftmeta = "layer(cmd_nav)";
          rightmeta = "layer(cmd_nav)";
        };
        "alt_nav:A" = {
          left = "C-left";
          right = "C-right";
          backspace = "C-backspace";
        };
        "cmd_nav:M" = {
          left = "home";
          right = "end";
          backspace = "macro(S-home backspace)";
        };
      };
    };
  };

  # PipeWire provides PulseAudio compatibility; keep the old PulseAudio daemon
  # disabled while still exposing Pulse clients through PipeWire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  # Kate is part of the desktop baseline rather than a project-specific editor.
  users.users.yiannis.packages = with pkgs; [
    kdePackages.kate
  ];
}
