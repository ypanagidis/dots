{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux (
  let
    version = "0.0.25-nightly.20260515.295";
    src = pkgs.fetchurl {
      url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
      hash = "sha256-aQqcSekj+hyShxwOWLRLa+NbH50pBWlkNBRL4IstksQ=";
    };

    t3Package = pkgs.callPackage ./t3.nix {
      inherit version src;
    };

    t3Contents = pkgs.appimageTools.extractType2 {
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
