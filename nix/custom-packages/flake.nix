{
  description = "Custom packages and overlays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # History note: this flake used to carry oxfmt/oxlint/tsgo binary pins,
  # the sst/opencode desktop app, nordvpn, and winapps. oxlint/oxfmt/
  # typescript-go and nordvpn are in nixpkgs now, the AI agent CLIs come
  # from the llm-agents input on the root flake, opencode-desktop comes from
  # OpenCode's official root-flake input, and winapps was dropped.
  outputs =
    { nix-vscode-extensions, ... }:
    {
      overlays.default =
        final: prev:
        let
          system = prev.stdenv.hostPlatform.system;
        in
        {
          # VSCode extensions
          nix-vscode-extensions = {
            vscode-marketplace = nix-vscode-extensions.extensions.${system}.vscode-marketplace;
            open-vsx = nix-vscode-extensions.extensions.${system}.open-vsx;
          };
        };
    };
}
