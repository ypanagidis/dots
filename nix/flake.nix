{
  description = "Yiannis' NixOS config";

  inputs = {
    # Track unstable for the whole system: this is what carries the newest
    # KDE Plasma (6.7.x as of Aug 2026). Stable releases lag a full Plasma
    # cycle behind.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # One flake for every AI coding agent (claude-code, codex, opencode,
    # gemini-cli, ...). Consumed directly via inputs.llm-agents.packages —
    # deliberately NOT following our nixpkgs so numtide's binary cache hits.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Declarative partitioning; disk-config.nix replaces the filesystem half
    # of hardware-configuration.nix.
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Helium browser, repackaged from upstream release binaries. The flake's
    # CI bumps version/hash on every Helium release, so updates ride
    # `nix flake update helium-flake` — replaces the old local pin + uh.
    # Swap for pkgs.helium-browser once the pending nixpkgs PR lands.
    helium-flake = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Terminal session daemon (zero-loss reattach when the terminal dies).
    # Config is dots/.config/herdr via dots.nix; kept on its own nixpkgs pin
    # since it builds with a rust-overlay toolchain.
    herdr.url = "github:herdrdev/herdr";

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    custom-packages = {
      url = "path:./custom-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Package niri-ctx from the pushed workspace source. The local Rust and
    # Bash bridge match this branch; pinning it in flake.lock keeps nested
    # path-flake evaluation pure and machine-independent.
    niri-workspace = {
      url = "github:ypanagidis/dots/niri";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      custom-packages,
      ...
    }@inputs:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          {
            nixpkgs.overlays = [ custom-packages.overlays.default ];
          }
          inputs.disko.nixosModules.disko
          ./disk-config.nix
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Leftover real files from the pre-NixOS backup restore get moved
            # aside instead of aborting activation.
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.sharedModules = [ inputs.plasma-manager.homeModules.plasma-manager ];
            home-manager.users.yiannis = import ./home.nix;
          }
        ];
      };
    };
}
