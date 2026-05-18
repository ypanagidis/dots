{
  description = "Custom packages and overlays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opencode-flake = {
      url = "github:sst/opencode";
    };

    claude = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nordvpn-flake = {
      url = "github:connerohnesorge/nordvpn-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs-unstable,
      nix-vscode-extensions,
      opencode-flake,
      claude,
      winapps,
      nordvpn-flake,
      ...
    }:
    {
      nixosModules = {
        nordvpn = nordvpn-flake.nixosModules.default;
        default = nordvpn-flake.nixosModules.default;
      };

      overlays.default =
        final: prev:
        let
          lib = prev.lib;
          system = prev.stdenv.hostPlatform.system;
          oxcAppsVersion = "1.65.0";
          oxcBinaryHashes = {
            x86_64-linux = {
              oxfmt = "sha256-kjwshpk6+hrn2NxsViXJm3gpTanoNCBuAIRGSmDPK7M=";
              oxlint = "sha256-TmN/rfL1ZnWNad85+JF8+QYBHK6ggO7Bbm4V+IeZ0rI=";
              target = "x86_64-unknown-linux-musl";
            };
          };
          tsgoBinaryHashes = {
            x86_64-linux = {
              hash = "sha512-qUrJWTB5/wv4wnRG0TRXElAxc2kykNiRNyEIEqBbLmzDlrcvAW7RRy8MXoY1ZyTiKGMu14itZ3x9oW6+blFpRw==";
              package = "native-preview-linux-x64";
            };
          };
          oxcBinaryForSystem =
            oxcBinaryHashes.${system} or (throw "Unsupported Oxc binary system: ${system}");
          tsgoBinaryForSystem =
            tsgoBinaryHashes.${system} or (throw "Unsupported tsgo binary system: ${system}");
          oxcBinary =
            pname: version:
            final.stdenvNoCC.mkDerivation {
              inherit pname version;

              src = final.fetchurl {
                url = "https://github.com/oxc-project/oxc/releases/download/apps_v${oxcAppsVersion}/${pname}-${oxcBinaryForSystem.target}.tar.gz";
                hash = oxcBinaryForSystem.${pname};
              };

              sourceRoot = ".";
              dontBuild = true;

              installPhase = ''
                runHook preInstall
                install -Dm755 ${pname}-${oxcBinaryForSystem.target} $out/bin/${pname}
                runHook postInstall
              '';

              meta = {
                mainProgram = pname;
                platforms = [ system ];
              };
            };
          tsgoBinary =
            version:
            final.stdenvNoCC.mkDerivation {
              pname = "tsgo";
              inherit version;

              src = final.fetchurl {
                url = "https://registry.npmjs.org/@typescript/${tsgoBinaryForSystem.package}/-/${tsgoBinaryForSystem.package}-${version}.tgz";
                inherit (tsgoBinaryForSystem) hash;
              };

              sourceRoot = "package";
              dontBuild = true;

              installPhase = ''
                runHook preInstall
                mkdir -p $out/lib/typescript-go $out/bin
                cp -R lib/* $out/lib/typescript-go/
                chmod +x $out/lib/typescript-go/tsgo
                ln -s $out/lib/typescript-go/tsgo $out/bin/tsgo
                runHook postInstall
              '';

              meta = {
                mainProgram = "tsgo";
                platforms = [ system ];
              };
            };
          hasSystemPackages =
            flake: builtins.hasAttr "packages" flake && builtins.hasAttr system flake.packages;
          hasPackage =
            flake: packageName:
            hasSystemPackages flake && builtins.hasAttr packageName flake.packages.${system};
          opencodePackage =
            package:
            package.overrideAttrs (old: {
              # Upstream currently requires bun 1.3.14, but the flake's
              # nixpkgs input still provides 1.3.13. Keep using the upstream
              # flake package while allowing that patch-level skew.
              postPatch = ''
                ${old.postPatch or ""}
                substituteInPlace package.json \
                  --replace-fail '"packageManager": "bun@1.3.14"' '"packageManager": "bun@1.3.13"'
              '';
            });
        in
        {
          # VSCode extensions
          nix-vscode-extensions = {
            vscode-marketplace = nix-vscode-extensions.extensions.${system}.vscode-marketplace;
            open-vsx = nix-vscode-extensions.extensions.${system}.open-vsx;
          };

          # pscale
          pscale = nixpkgs-unstable.legacyPackages.${system}.pscale;

          # Oxc publishes prebuilt CLI binaries on the apps release.
          oxfmt = oxcBinary "oxfmt" "1.65.0";

          oxlint = oxcBinary "oxlint" "1.65.0";

          # tailwindcss-language-server 0.14.29 (latest)
          tailwindcss-language-server = prev.tailwindcss-language-server.overrideAttrs (old: rec {
            version = "0.14.29";
            src = final.applyPatches {
              src = final.fetchFromGitHub {
                owner = "tailwindlabs";
                repo = "tailwindcss-intellisense";
                tag = "v${version}";
                hash = "sha256-o5NyU52j3ZyuKWT4lL5U78qz4TBbXerylTl2fdvwqlk=";
              };
              postPatch = ''
                substituteInPlace packages/tailwindcss-language-server/package.json \
                  --replace-fail '"@tailwindcss/oxide": "^4.1.15"' '"@tailwindcss/oxide": "^4.1.14"'
              '';
            };
            pnpmDeps = final.fetchPnpmDeps {
              inherit src version;
              pname = old.pname;
              pnpmWorkspaces = old.pnpmWorkspaces;
              pnpm = final.pnpm_9;
              fetcherVersion = 1;
              hash = "sha256-wY/tJSh5LUttBVNipU1lLF2jfhX99tK3QP4yZUlp/zw=";
            };
          });

          # TypeScript publishes prebuilt native preview binaries on npm.
          tsgo = tsgoBinary "7.0.0-dev.20260421.2";
        }
        // lib.optionalAttrs (hasPackage opencode-flake "opencode") {
          opencode = opencodePackage opencode-flake.packages.${system}.opencode;
        }
        // lib.optionalAttrs (hasPackage opencode-flake "opencode-desktop") {
          opencode-desktop = opencodePackage opencode-flake.packages.${system}.opencode-desktop;
        }
        // lib.optionalAttrs (hasPackage claude "default") {
          claude = claude.packages.${system}.default;
        }
        // lib.optionalAttrs (hasPackage nordvpn-flake "nordvpn") {
          nordvpn = nordvpn-flake.packages.${system}.nordvpn;
        }
        //
          lib.optionalAttrs
            (prev.stdenv.isLinux && hasPackage winapps "winapps" && hasPackage winapps "winapps-launcher")
            {
              winapps = winapps.packages.${system}.winapps;
              winapps-launcher = winapps.packages.${system}.winapps-launcher;
            };
    };
}
