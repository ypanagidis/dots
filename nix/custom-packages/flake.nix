{
  description = "Custom packages and overlays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # History note: this flake used to carry oxfmt/oxlint/tsgo binary pins and
  # the sst/opencode desktop app. oxlint/oxfmt/typescript-go are in nixpkgs
  # now, the AI agent CLIs come from the llm-agents input on the root flake,
  # and opencode-desktop was dropped.
  outputs =
    {
      nix-vscode-extensions,
      winapps,
      ...
    }:
    {
      overlays.default =
        final: prev:
        let
          lib = prev.lib;
          system = prev.stdenv.hostPlatform.system;
          hasSystemPackages =
            flake: builtins.hasAttr "packages" flake && builtins.hasAttr system flake.packages;
          hasPackage =
            flake: packageName:
            hasSystemPackages flake && builtins.hasAttr packageName flake.packages.${system};
        in
        {
          # VSCode extensions
          nix-vscode-extensions = {
            vscode-marketplace = nix-vscode-extensions.extensions.${system}.vscode-marketplace;
            open-vsx = nix-vscode-extensions.extensions.${system}.open-vsx;
          };
        }
        //
          lib.optionalAttrs
            (
              prev.stdenv.hostPlatform.isLinux
              && hasPackage winapps "winapps"
              && hasPackage winapps "winapps-launcher"
            )
            {
              winapps = winapps.packages.${system}.winapps;
              winapps-launcher = winapps.packages.${system}.winapps-launcher;
            };
    };
}
