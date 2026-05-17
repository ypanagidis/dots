{ pkgs, ... }:

{
  # User-facing media tools. Runtime codec libraries used by wrappers stay in
  # their wrapper modules instead of being mixed into this list.
  home.packages = with pkgs; [
    ffmpeg-full
  ];
}
