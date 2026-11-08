{ ... }:

{
  # Plasma remains the default desktop. Niri and Hyprland are independent
  # login sessions sharing the Noctalia shell; it and the workflow helpers
  # only start after selecting one of them in SDDM.
  imports = [
    ./kde.nix
    ./noctalia.nix
    ./niri.nix
    ./hyprland.nix
  ];
}
