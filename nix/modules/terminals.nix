{ pkgs, dotsLink, ... }:

{
  # Ghostty: the package is declared here, the config (incl. themes/) is the
  # shared dots/ copy — same file the Arch install symlinks. See dots.nix.
  home.packages = [ pkgs.ghostty ];

  xdg.configFile."ghostty".source = dotsLink ".config/ghostty";
}
