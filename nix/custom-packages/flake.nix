{
  description = "Custom packages and overlays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Kept only for opencode-desktop, which llm-agents does not package.
    # The AI agent CLIs come from the llm-agents input on the root flake.
    opencode-flake = {
      url = "github:sst/opencode";
    };

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nix-vscode-extensions,
      opencode-flake,
      winapps,
      ...
    }:
    {
      overlays.default =
        final: prev:
        let
          lib = prev.lib;
          system = prev.stdenv.hostPlatform.system;
          oxcAppsVersion = "1.66.0";
          oxcBinaryHashes = {
            x86_64-linux = {
              oxfmt = "sha256-zdZm2G0TVf+UNmAmyWyUa+dkjkpKEskOw6Vb/ihVFr4=";
              oxlint = "sha256-eTOo/blrJjTfJKbtkWXF9n9D4ql9RFRAvBwXcJLSPic=";
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

          # Oxc publishes prebuilt CLI binaries on the apps release.
          oxfmt = oxcBinary "oxfmt" "1.66.0";

          oxlint = oxcBinary "oxlint" "1.66.0";

          # tailwindcss-language-server: the 0.14.29 pin was upstreamed;
          # nixpkgs unstable now ships it natively, so no override.

          # TypeScript publishes prebuilt native preview binaries on npm.
          tsgo = tsgoBinary "7.0.0-dev.20260421.2";
        }
        // lib.optionalAttrs (hasPackage opencode-flake "opencode-desktop") {
          opencode-desktop = opencodePackage opencode-flake.packages.${system}.opencode-desktop;
        }
        //
          lib.optionalAttrs
            (prev.stdenv.hostPlatform.isLinux && hasPackage winapps "winapps" && hasPackage winapps "winapps-launcher")
            {
              winapps = winapps.packages.${system}.winapps;
              winapps-launcher = winapps.packages.${system}.winapps-launcher;
            };
    };
}
