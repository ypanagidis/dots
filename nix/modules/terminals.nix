{ pkgs, dotsLink, ... }:

{
  # Alacritty is the default terminal; Ghostty remains available as a fallback.
  # Both configs are shared dots/ copies, matching the non-NixOS setup.
  home.packages = [
    pkgs.alacritty
    pkgs.ghostty
  ];

  xdg.configFile."alacritty".source = dotsLink ".config/alacritty";
  xdg.configFile."ghostty".source = dotsLink ".config/ghostty";
}
