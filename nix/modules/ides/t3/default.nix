{
  pkgs,
  lib,
  osConfig,
  ...
}:

# T3 Code updates itself, like on macOS: electron-updater polls the nightly
# feed and swaps the AppImage at $APPIMAGE in place. That needs a writable
# AppImage run through appimage-run (which exports APPIMAGE), plus the binfmt
# registration from modules/compat/electron-runtime.nix so the updater can
# relaunch the new file directly. The version pinned here only seeds a fresh
# install; refresh it with ./update-t3.sh when convenient.
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

        exec ${lib.getExe osConfig.programs.appimage.package} "$app" "$@"
      '';
    };
  in
  {
    home.packages = [ t3Launcher ];

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
