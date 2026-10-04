{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  # The SDK, emulator images and Gradle are managed by the IDE's own SDK
  # Manager under ~/Android/Sdk. The emulator needs /dev/kvm; the user is
  # already in the kvm group (configuration.nix).
  home.packages = [ pkgs.android-studio ];

  # Same launch env as the IntelliJ entry: Android Studio is built on the
  # JetBrains platform (non-reparenting WM under niri). The emulator it
  # spawns bundles a Qt without the Wayland plugin and aborts at startup
  # when it inherits the session's QT_QPA_PLATFORM=wayland, so force xcb.
  xdg.desktopEntries.android-studio = {
    name = "Android Studio";
    genericName = "Android IDE";
    exec = "env _JAVA_AWT_WM_NONREPARENTING=1 QT_QPA_PLATFORM=xcb android-studio";
    terminal = false;
    categories = [
      "Development"
      "IDE"
    ];
    icon = "android-studio";
    settings.StartupWMClass = "jetbrains-studio";
  };
}
