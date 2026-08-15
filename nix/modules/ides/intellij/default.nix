{ pkgs, lib, ... }:

let
  # JetBrains discontinued the separate Community edition (2025 unified
  # distribution plan); `jetbrains.idea` is the unified IDE with the free
  # tier. The old idea-oss package is stuck on an insecure-flagged version.
  ideaPackage = pkgs.jetbrains.idea;
  selector = "IntelliJIdea${lib.versions.majorMinor ideaPackage.version}";
in
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.packages = [ ideaPackage ];

  xdg.configFile."JetBrains/${selector}/idea64.vmoptions".source = ./vm-config.txt;

  xdg.desktopEntries.idea = {
    name = "IntelliJ IDEA";
    genericName = "Java and Kotlin IDE";
    exec = "env _JAVA_AWT_WM_NONREPARENTING=1 idea";
    terminal = false;
    categories = [ "Development" ];
    icon = "idea";
  };
}
