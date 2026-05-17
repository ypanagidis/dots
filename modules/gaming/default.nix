{ pkgs, ... }:

{
  # User-level gaming helpers. Steam/gamemode stay in the NixOS Steam module
  # because they configure system integration and firewall behavior.
  home.packages = with pkgs; [
    protonup-qt
    protontricks
    mangohud
  ];
}
