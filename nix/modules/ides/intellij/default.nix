{ pkgs, lib, ... }:

let
  ideaPackage = pkgs.jetbrains.idea-oss;
  selector = "IdeaIC${lib.versions.majorMinor ideaPackage.version}";
in
lib.mkIf pkgs.stdenv.isLinux {
  home.packages = [ ideaPackage ];

  xdg.configFile."JetBrains/${selector}/idea64.vmoptions".source = ./vm-config.txt;

  xdg.desktopEntries.idea-oss = {
    name = "IntelliJ IDEA Community";
    genericName = "Java and Kotlin IDE";
    exec = "env _JAVA_AWT_WM_NONREPARENTING=1 idea-oss";
    terminal = false;
    categories = [ "Development" ];
    icon = "idea-oss";
  };
}
