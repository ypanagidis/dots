{
  config,
  pkgs,
  pkgsMaster,
  lib,
  ...
}:
let
  # From nix-vscode-extensions overlay:
  # pkgs.nix-vscode-extensions.{vscode-marketplace, open-vsx, ...}
  mkt = pkgs.nix-vscode-extensions.vscode-marketplace;
  vsc = pkgs.vscode-extensions;

  repoRoot = "${config.home.homeDirectory}/nixcfg";
  repoSettings = "${repoRoot}/modules/ides/vscode/settings.json";
  repoKeybindings = "${repoRoot}/modules/ides/vscode/keybindings.json";
  vscodePkg = pkgsMaster.vscode;

  vscodeLauncher = pkgs.writeShellScript "vscode-launcher" ''
    if [ "$#" -gt 0 ]; then
      case "$1" in
        vscode://*)
          exec ${vscodePkg}/bin/code --reuse-window --open-url "$@"
          ;;
      esac
    fi

    exec ${vscodePkg}/bin/code --reuse-window "$@"
  '';
in
{
  # Migrate existing mutable files back into the repo once, then let HM
  # symlink VS Code's live files to the repo so edits stay nix-managed.
  home.activation.vscodeMigrateUserConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    userDir="$HOME/.config/Code/User"
    settingsFile="$userDir/settings.json"
    keybindingsFile="$userDir/keybindings.json"
    repoSettingsFile="${repoSettings}"
    repoKeybindingsFile="${repoKeybindings}"

    mkdir -p "$userDir"

    if [ -L "$settingsFile" ]; then
      target="$(readlink "$settingsFile" || true)"
      case "$target" in
        "$repoSettingsFile")
          :
          ;;
        /nix/store/*)
          rm "$settingsFile"
          ;;
        *)
          rm "$settingsFile"
          ;;
      esac
    elif [ -f "$settingsFile" ]; then
      cp "$settingsFile" "$repoSettingsFile"
      rm "$settingsFile"
    fi

    if [ -L "$keybindingsFile" ]; then
      target="$(readlink "$keybindingsFile" || true)"
      case "$target" in
        "$repoKeybindingsFile")
          :
          ;;
        /nix/store/*)
          rm "$keybindingsFile"
          ;;
        *)
          rm "$keybindingsFile"
          ;;
      esac
    elif [ -f "$keybindingsFile" ]; then
      cp "$keybindingsFile" "$repoKeybindingsFile"
      rm "$keybindingsFile"
    fi
  '';

  xdg.configFile."Code/User/settings.json".source = config.lib.file.mkOutOfStoreSymlink repoSettings;
  xdg.configFile."Code/User/settings.json".force = true;
  xdg.configFile."Code/User/keybindings.json".source =
    config.lib.file.mkOutOfStoreSymlink repoKeybindings;
  xdg.configFile."Code/User/keybindings.json".force = true;

  xdg.desktopEntries.code = lib.mkIf pkgs.stdenv.isLinux {
    name = "Visual Studio Code";
    genericName = "Text Editor";
    comment = "Code Editing. Redefined.";
    exec = "${vscodeLauncher} %U";
    terminal = false;
    categories = [
      "Utility"
      "TextEditor"
      "Development"
      "IDE"
    ];
    icon = "vscode";
    startupNotify = true;
    mimeType = [ "x-scheme-handler/vscode" ];
    settings = {
      StartupWMClass = "Code";
      Keywords = "vscode";
    };
  };

  xdg.desktopEntries.code-url-handler = lib.mkIf pkgs.stdenv.isLinux {
    name = "Visual Studio Code - URL Handler";
    noDisplay = true;
    exec = "${vscodeLauncher} %U";
    terminal = false;
    icon = "vscode";
    startupNotify = true;
    settings = {
      StartupWMClass = "Code";
      Hidden = "true";
    };
  };

  xdg.mimeApps.defaultApplications."x-scheme-handler/vscode" = "code.desktop";

  home.activation.vscodeMutableExtensionsDir = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    extDir="$HOME/.vscode/extensions"

    if [ -L "$extDir" ]; then
      target="$(readlink "$extDir" || true)"
      case "$target" in
        /nix/store/*)
          rm "$extDir"
          ;;
      esac
    fi

    mkdir -p "$extDir"
  '';

  home.packages = [
    pkgs.nixfmt
  ];

  programs.vscode = {
    enable = true;
    package = vscodePkg;

    # Allow installing any extra extensions directly in VS Code.
    mutableExtensionsDir = true;

    profiles.default.extensions = [
      # Vim + TS native preview
      mkt.vscodevim.vim
      mkt.typescriptteam."native-preview"

      # Your existing stuff (marketplace versions)
      mkt.jnoortheen."nix-ide"
      mkt.bbenoist.nix
      mkt.esbenp."prettier-vscode"
      mkt.dbaeumer."vscode-eslint"
      mkt.editorconfig.editorconfig
      mkt.eamodio.gitlens

      # Remote development (SSH)
      vsc.ms-vscode-remote.remote-ssh
      vsc.ms-vscode-remote.remote-ssh-edit

      #Themes
      mkt.sdras."night-owl"
      mkt.teabyii.ayu
    ];
  };
}
