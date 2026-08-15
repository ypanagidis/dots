{ pkgs, dotsLink, ... }:

{
  # btop: package declared here, config + themes are the shared dots/ copy
  # (theme "dots" is generated from the ghostty palette; the old cyberdream/
  # ayu/catppuccin themes moved to dots/.config/btop/themes too).
  home.packages = [ pkgs.btop ];

  xdg.configFile."btop".source = dotsLink ".config/btop";
}
