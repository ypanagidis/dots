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
    lib.optionals pkgs.stdenv.isLinux
    (with pkgs; [
      discord
      libreoffice-fresh
      opencode-desktop
      pavucontrol
      remmina
      high-tide
      haruna
      bruno
      obsidian
    ])
    ++ lib.optionals (pkgs ? winapps) [
      pkgs.winapps
      pkgs.winapps-launcher
    ];

  xdg.desktopEntries.opencode-desktop = lib.mkIf pkgs.stdenv.isLinux {
    name = "OpenCode";
    genericName = "Coding Agent";
    comment = "Desktop app for OpenCode";
    exec = "env XDG_DATA_HOME=${home}/.local/share XDG_CONFIG_HOME=${home}/.config XDG_STATE_HOME=${home}/.local/state XDG_CACHE_HOME=${home}/.cache ${pkgs.opencode-desktop}/bin/opencode-desktop";
    terminal = false;
    categories = [ "Development" ];
    icon = "applications-development";
    startupNotify = true;
    # The Nix-built OpenCode wrapper runs the generic Electron binary, so KWin
    # reports the live window class as "electron". Matching that lets KDE
    # activate the existing single-instance window instead of spawning a
    # transient second Electron process from the launcher shortcut.
    settings = {
      StartupWMClass = "electron";
    };
  };

  # WinApps is userland configuration and should travel with the WinApps HM
  # packages instead of living in the root `home.nix`.
  xdg.configFile."winapps/winapps.conf".text = lib.mkIf pkgs.stdenv.isLinux ''
    RDP_USER="yiannis"
    RDP_PASS="fuckwindows"
    RDP_DOMAIN=""
    RDP_IP="192.168.122.85"
    WAFLAVOR="libvirt"
  '';
}
