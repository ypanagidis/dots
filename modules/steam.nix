{
  config,
  pkgs,
  lib,
  options,
  ...
}:

let
  hasGraphics = lib.hasAttrByPath [ "hardware" "graphics" ] options;
  hasOpenGL = lib.hasAttrByPath [ "hardware" "opengl" ] options;
in
{
  config = lib.mkMerge [
    {
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;

        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
      };

      hardware.steam-hardware.enable = true;
      programs.gamemode.enable = true;
    }

    (lib.optionalAttrs hasGraphics {
      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;
    })

  ];
}
