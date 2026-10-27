{
  pkgs,
  lib,
  osConfig,
  ...
}:

# T3 Code runs from a writable AppImage through appimage-run (which exports
# APPIMAGE), plus the binfmt registration from
# modules/compat/electron-runtime.nix so the app can relaunch the file
# directly. The upstream nightly pinned here only seeds a fresh install;
# t3-code-fork-update (below) then replaces it with private fork builds, and
# the launcher turns the in-app updater off. Refresh the seed with
# ./update-t3.sh if needed.
lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
  let
    version = "0.0.46-nightly.20261004.2648";
    src = pkgs.fetchurl {
      url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
      hash = "sha256-mYkVWOb+5nmtiO1CQP3yW3kwzGQYYe3Sp+Hnt0nS6/A=";
    };

    t3Contents = pkgs.appimageTools.extract {
      pname = "t3-code";
      inherit version src;
    };

    t3Launcher = pkgs.writeShellApplication {
      name = "t3-code";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        data="''${XDG_DATA_HOME:-$HOME/.local/share}/t3-code"
        # No version in the file name, so the updater overwrites it in place.
        app="$data/T3-Code.AppImage"
        cache="''${XDG_CACHE_HOME:-$HOME/.cache}/appimage-run"

        if [ ! -e "$app" ]; then
          mkdir -p "$data"
          install -m 755 ${src} "$app"
        fi

        # appimage-run unpacks each AppImage into $cache/<sha256> and never
        # cleans up. Drop T3 unpacks left behind by earlier versions.
        current=$(sha256sum "$app" | cut -d' ' -f1)
        for dir in "$cache"/*/; do
          dir=''${dir%/}
          if [ "''${dir##*/}" != "$current" ] && [ -e "$dir/t3code.desktop" ]; then
            rm -rf "$dir"
          fi
        done

        # Fork builds point at a private feed the app can't read; updates come
        # from t3-code-fork-update instead.
        export T3CODE_DISABLE_AUTO_UPDATE=1
        exec ${lib.getExe osConfig.programs.appimage.package} "$app" "$@"
      '';
    };

    # Builds from the private fork (ypanagidis/t3code, branch `fork`): upstream
    # nightly plus local patches, published daily by its fork-nightly workflow.
    # Those builds have no in-app update feed, so this swaps the AppImage
    # instead; the running app keeps its old file until restarted.
    t3ForkUpdate = pkgs.writeShellApplication {
      name = "t3-code-fork-update";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gh
        pkgs.libnotify
      ];
      text = ''
        repo="ypanagidis/t3code"
        data="''${XDG_DATA_HOME:-$HOME/.local/share}/t3-code"
        app="$data/T3-Code.AppImage"
        stamp="$data/fork-release"

        # Offline or signed out: try again next tick.
        if ! tag=$(gh release view --repo "$repo" --json tagName --jq .tagName); then
          exit 0
        fi
        if [ "$(cat "$stamp" 2>/dev/null)" = "$tag" ]; then
          exit 0
        fi

        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        gh release download "$tag" --repo "$repo" --pattern T3-Code.AppImage --dir "$tmp"
        mkdir -p "$data"
        install -m 755 "$tmp/T3-Code.AppImage" "$app.new"
        mv -f "$app.new" "$app"
        printf '%s\n' "$tag" > "$stamp"
        notify-send --app-name "T3 Code" "T3 Code updated" "$tag is installed. Restart T3 Code to use it." || true
      '';
    };
  in
  {
    home.packages = [
      t3Launcher
      t3ForkUpdate
    ];

    systemd.user.services.t3-code-fork-update = {
      Unit = {
        Description = "Install the newest T3 Code fork build";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe t3ForkUpdate;
      };
    };

    systemd.user.timers.t3-code-fork-update = {
      Unit.Description = "Check for new T3 Code fork builds";
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1h";
        Unit = "t3-code-fork-update.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };

    xdg.desktopEntries.t3-code = {
      name = "T3 Code";
      genericName = "Coding Agent GUI";
      comment = "Desktop GUI for coding agents";
      exec = "${lib.getExe t3Launcher} %U";
      terminal = false;
      categories = [ "Development" ];
      icon = "${t3Contents}/usr/share/icons/hicolor/512x512/apps/t3code.png";
      mimeType = [ "x-scheme-handler/t3code" ];
      settings.StartupWMClass = "com.t3tools.T3Code";
    };

    # The app tries to register this itself, but HM owns mimeapps.list.
    xdg.mimeApps.defaultApplications."x-scheme-handler/t3code" = "t3-code.desktop";
  }
)
