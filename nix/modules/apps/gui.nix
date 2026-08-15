{
  config,
  pkgs,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;
in

{
  # User-facing desktop applications. These do not need to be system packages,
  # so they live in the Home Manager profile.
  home.packages =
    lib.optionals pkgs.stdenv.hostPlatform.isLinux
    (with pkgs; [
      discord
      libreoffice-fresh
      pavucontrol
      remmina
      high-tide
      haruna
      bruno
      obsidian
    ]);

  # Native-Wayland Electron missizes Discord's maximized surface on the
  # rotated portrait ultrawide and crops the right edge — at any output scale
  # (verified live 2026-08-15; neither WaylandPerSurfaceScale/WaylandUiScale
  # nor disabling WaylandFractionalScaleV1 fixed it on Electron 42). XWayland
  # renders it correctly, matching how it worked on the old Arch setup.
  xdg.desktopEntries.discord = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    name = "Discord";
    genericName = "Internet Messenger";
    icon = "discord";
    exec = "env -u NIXOS_OZONE_WL discord --ozone-platform=x11 %U";
    terminal = false;
    mimeType = [ "x-scheme-handler/discord" ];
    categories = [
      "Network"
      "InstantMessaging"
    ];
    settings.StartupWMClass = "discord";
  };
}
