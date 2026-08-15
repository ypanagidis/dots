{ pkgs, inputs, ... }:

{
  # herdr binary from its upstream flake; its config.toml comes from dots/
  # (linked in modules/dots.nix alongside the other shared configs).
  home.packages = [ inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
