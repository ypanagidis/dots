{ pkgs, ... }:

let
  # Argyll 3.4.1 (nixpkgs) opens the Datacolor SpyderExpress (Spyder 2024
  # family, 085c:0a0b) but every reading comes back as XYZ 1,1,1. 3.5.0 fixed
  # "some models of Spyder2024" and measures it correctly (checked
  # 2026-11-10). Drop this once nixpkgs ships >= 3.5.0.
  argyllcms = pkgs.argyllcms.overrideAttrs (old: {
    version = "3.5.0";
    src = pkgs.fetchurl {
      url = "https://www.argyllcms.com/Argyll_V3.5.0_src.zip";
      hash = "sha256-+Fds5Vif0VYgq7c/8EnqMfVd29G7ptH/qHRSZY57yF8=";
    };
    # The bundled zlib trips GCC 14's stricter C defaults.
    env = (old.env or { }) // {
      NIX_CFLAGS_COMPILE = "-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=incompatible-pointer-types";
    };
  });
in
{
  # User-facing media tools. Runtime codec libraries used by wrappers stay in
  # their wrapper modules instead of being mixed into this list.
  home.packages = with pkgs; [
    ffmpeg-full
    spotify
    # Display calibration with the Datacolor Spyder: Argyll measures,
    # DisplayCAL drives it. The resulting ICC goes on the Hyprland monitor rule.
    argyllcms
    (displaycal.override { inherit argyllcms; })
  ];

  # No desktop-entry override: with the global NIXOS_OZONE_WL=1 the spotify
  # wrapper unsets DISPLAY and CEF runs native Wayland. The old CachyOS-era
  # XWayland workaround (env -u NIXOS_OZONE_WL + --ozone-platform=x11) lives
  # in git history if the 5K flicker ever comes back.
}
