{ ... }:

{
  # Main is KDE-only now. Niri experiments were removed from this branch and
  # remain available on `multihost-config`.
  imports = [
    ./kde.nix
  ];
}
