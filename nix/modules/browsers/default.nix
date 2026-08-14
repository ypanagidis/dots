{ pkgs, ... }:

{
  imports = [
    ./helium
  ];

  # Browser policy lives here so we can see the intentional overlap. Helium is
  # configured as the default in `./helium`; Chromium and Chrome are kept for
  # compatibility/testing until you decide to trim one.
  programs.firefox = {
    enable = true;
    policies.Preferences."apz.gtk.touchpad_pinch.enabled" = {
      Value = true;
      Status = "default";
    };
  };
  home.packages = with pkgs; [
    chromium
    google-chrome
  ];
}
