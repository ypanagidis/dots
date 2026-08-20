{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
  let
    version = "0.0.34-nightly.20260819.1133";
    src = pkgs.fetchurl {
      url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
      hash = "sha256-kWg8I3CVWKROnIozOPK40crIAAhBCA2wjmaLCLR+DF4=";
    };

    t3Package = pkgs.callPackage ./t3.nix {
      inherit version src;
    };

    t3Contents = pkgs.appimageTools.extract {
      pname = "t3-code";
      inherit version src;
    };
  in
  {
    home.packages = [ t3Package ];

    xdg.desktopEntries.t3-code = {
      name = "T3 Code";
      genericName = "Coding Agent GUI";
      comment = "Desktop GUI for coding agents";
      exec = "${t3Package}/bin/t3-code";
      terminal = false;
      categories = [ "Development" ];
      icon = "${t3Contents}/usr/share/icons/hicolor/1024x1024/apps/t3-code-desktop.png";
    };
  }
)
