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
        # logid exposes the MX Master thumb button through a 0000:0000 virtual
        # keyboard. Do not let keyd re-emit that KEY_F13 into KDE shortcuts.
        "-0000:0000"
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
