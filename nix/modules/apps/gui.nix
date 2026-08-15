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
    ])
    ++ lib.optionals (pkgs ? winapps) [
      pkgs.winapps
      pkgs.winapps-launcher
    ];

  # WinApps is userland configuration and should travel with the WinApps HM
  # packages instead of living in the root `home.nix`.
  xdg.configFile."winapps/winapps.conf".text = lib.mkIf pkgs.stdenv.hostPlatform.isLinux ''
    RDP_USER="yiannis"
    RDP_PASS="fuckwindows"
    RDP_DOMAIN=""
    RDP_IP="192.168.122.85"
    WAFLAVOR="libvirt"
  '';
}
