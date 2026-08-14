{
  lib,
  appimageTools,
  libnotify,
  version,
  src,
  xorg,
}:

appimageTools.wrapType2 {
  pname = "t3-code";
  inherit version src;

  extraPkgs =
    pkgs: with pkgs; [
      libnotify
      xorg.libxkbfile
    ];

  meta = {
    description = "Desktop GUI for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3-code";
  };
}
