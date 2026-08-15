{ ... }:

{
  # Plasma remains the default desktop. Niri is an independent login session;
  # its shell and workflow helpers only start after selecting Niri in SDDM.
  imports = [
    ./kde.nix
    ./niri.nix
  ];
}
