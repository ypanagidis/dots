{ pkgs, ... }:

{
  # User-facing media tools. Runtime codec libraries used by wrappers stay in
  # their wrapper modules instead of being mixed into this list.
  home.packages = with pkgs; [
    ffmpeg-full
    spotify
  ];

  xdg.desktopEntries.spotify = {
    name = "Spotify";
    genericName = "Music Player";
    icon = "spotify-client";
    exec = "env -u NIXOS_OZONE_WL spotify --ozone-platform=x11 %U";
    terminal = false;
    mimeType = [ "x-scheme-handler/spotify" ];
    categories = [
      "Audio"
      "Music"
      "Player"
      "AudioVideo"
    ];
    settings.StartupWMClass = "spotify";
  };
}
