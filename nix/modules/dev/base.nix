{ pkgs, ... }:

{
  programs.java = {
    enable = true;
    package = pkgs.jdk21;
  };

  # General development CLIs that should be available in normal user shells.
  # AI agents live in ./ai.nix.
  home.packages = with pkgs; [
    fnm
    pnpm
    nodejs
    python3
    bun
    (maven.override { jdk_headless = pkgs.jdk21; })
    httpie
    pscale
    graphite-cli
    google-cloud-sdk # gcloud + bq: BigQuery inspection with the Doppler service account
    playwright-mcp
  ];
}
