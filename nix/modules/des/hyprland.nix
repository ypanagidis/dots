{
  config,
  inputs,
  pkgs,
  dotsLink,
  ...
}:

let
  hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
in
{
  # The Lua config lives in dots/ like niri's KDL, edited live without a
  # rebuild; `hyprctl reload` (or saving, via inotify) applies it.
  xdg.configFile."hypr".source = dotsLink ".config/hypr";

  # UWSM exports this to the systemd activation environment, so portals and
  # apps launched through `uwsm app` see it too (unlike hl.env). The KDE
  # platform theme gives Qt apps Breeze Dark from kdeglobals; without it the
  # KDE portal, which answers the Settings portal here, reads Qt's default
  # light palette and tells every app (Helium included) to go light.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export QT_QPA_PLATFORMTHEME=kde
    export XCURSOR_THEME=breeze_cursors
    export XCURSOR_SIZE=24
  '';

  home.packages = with pkgs; [
    grimblast
    hyprpicker
    wl-clipboard
  ];

  # Catch Lua errors (unknown keys, bad dispatcher arguments) during Home
  # Manager activation, before the next login. Hyprland refuses to run
  # without XDG_RUNTIME_DIR and binds an IPC socket there even in verify
  # mode; activation at boot has no runtime dir, so give it a throwaway one.
  home.activation.validateHyprlandConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    hypr_runtime="$(mktemp -d)"
    if ! XDG_RUNTIME_DIR="$hypr_runtime" ${hyprland}/bin/Hyprland --verify-config \
      --config ${config.xdg.configHome}/hypr/hyprland.lua >"$hypr_runtime/verify.log" 2>&1; then
      sed -n '/Config parsing result/,$p' "$hypr_runtime/verify.log" >&2
      rm -rf "$hypr_runtime"
      exit 1
    fi
    rm -rf "$hypr_runtime"
  '';
}
