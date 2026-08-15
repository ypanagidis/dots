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
}
