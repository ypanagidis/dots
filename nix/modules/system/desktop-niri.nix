{ pkgs, ... }:

let
  niriVramFixed = pkgs.callPackage ../../packages/niri-vram-fixed.nix { };
in

{
  # Install Niri beside Plasma. Keep Plasma explicit so enabling programs.niri
  # cannot change the session SDDM selects by default.
  programs.niri = {
    enable = true;
    package = niriVramFixed;
    useNautilus = false;
  };
  services.displayManager.defaultSession = "plasma";

  # Niri discovers xwayland-satellite automatically when it is on PATH.
  environment.systemPackages = [ pkgs.xwayland-satellite ];

  # Match the workaround used on the old CachyOS setup. Deliberately apply it
  # only to Niri for the A/B run: Noctalia remains untreated so its own VRAM
  # remains visible independently of the driver workaround.
  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-niri-vram".text = builtins.toJSON {
    rules = [
      {
        pattern = {
          feature = "procname";
          matches = "niri";
        };
        profile = "No Niri VidMem Reuse";
      }
    ];
    profiles = [
      {
        name = "No Niri VidMem Reuse";
        settings = [
          {
            key = "GLVidHeapReuseRatio";
            value = 0;
          }
        ];
      }
    ];
  };
}
