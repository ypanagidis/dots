{ pkgs, ... }:

{
  # User-facing media tools. Runtime codec libraries used by wrappers stay in
  # their wrapper modules instead of being mixed into this list.
  home.packages = with pkgs; [
    ffmpeg-full
    spotify
  ];

  # No desktop-entry override: with the global NIXOS_OZONE_WL=1 the spotify
  # wrapper unsets DISPLAY and CEF runs native Wayland. The old CachyOS-era
  # XWayland workaround (env -u NIXOS_OZONE_WL + --ozone-platform=x11) lives
  # in git history if the 5K flicker ever comes back.
}
