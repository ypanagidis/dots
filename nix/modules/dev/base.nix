{ pkgs, ... }:

{
  # General development CLIs that should be available in normal user shells.
  # AI agents live in ./ai.nix.
  home.packages = with pkgs; [
    fnm
    pnpm
    nodejs
    python3
    bun
    httpie
    pscale
    graphite-cli
    playwright-mcp
  ];
}
