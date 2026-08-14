{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  home.packages = with pkgs; [
    jetbrains.datagrip
  ];

  xdg.configFile."JetBrains/DataGrip2025.3/datagrip64.vmoptions".source = ./vm-config.txt;
}
