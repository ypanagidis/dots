{ inputs, pkgs, ... }:

let
  hyprlandPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in

{
  # Hyprland from its own flake (see flake.nix), with nixpkgs' module rather
  # than the flake's: upstream's module still writes the hyprlang config that
  # 0.57 no longer reads. The portal must come from the same flake revision.
  programs.hyprland = {
    enable = true;
    package = hyprlandPkgs.hyprland;
    portalPackage = hyprlandPkgs.xdg-desktop-portal-hyprland;
    # Adds the "Hyprland (uwsm-managed)" SDDM entry: graphical-session.target,
    # XDG autostart, and per-app systemd scopes. Use that one, not plain
    # "Hyprland".
    withUWSM = true;
  };

  # hyprland.cachix.org builds the flake against its own nixpkgs pin. Only
  # takes effect after the first switch that includes it, so the very first
  # build passes the same values with --option (see readme.md).
  nix.settings = {
    extra-substituters = [ "https://hyprland.cachix.org" ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  # Hyprland's portal handles screencast, screenshots, and global shortcuts;
  # file pickers and settings (dark mode) come from the KDE portal that Plasma
  # already installs, so dialogs look the same in every session.
  xdg.portal.config.hyprland = {
    default = [
      "hyprland"
      "kde"
    ];
    "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
    "org.freedesktop.impl.portal.Settings" = [ "kde" ];
  };
}
