{
  pkgs,
  lib,
  dotsLink,
  ...
}:

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

  # IdeaVim reads $XDG_CONFIG_HOME/ideavim/ideavimrc. The file is the nvim
  # keymap port in dots/, linked out-of-store so edits apply on :source
  # without a rebuild.
  xdg.configFile."ideavim/ideavimrc".source = dotsLink ".config/ideavim/ideavimrc";

  # Companion IDE keymap (Ctrl+J/K in popups, which IdeaVim cannot bind).
  # The IDE only lists it; it must be selected once in Settings > Keymap.
  # Editing it from the IDE settings UI fails (read-only link) — edit the
  # file in dots/ instead.
  xdg.configFile."JetBrains/${selector}/keymaps/Neovim.xml".source =
    dotsLink ".config/JetBrains/keymaps/Neovim.xml";

  xdg.desktopEntries.idea = {
    name = "IntelliJ IDEA";
    genericName = "Java and Kotlin IDE";
    exec = "env _JAVA_AWT_WM_NONREPARENTING=1 idea";
    terminal = false;
    categories = [ "Development" ];
    icon = "idea";
  };
}
