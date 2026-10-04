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

          # Release tags are v<port>+wispr<app>; bump with update-wispr-flow.sh.
          wisprAppVersion = "1.6.957";
          wisprPortVersion = "1.0.4";
          wisprFlowVersion = "${wisprAppVersion}-${wisprPortVersion}";
          wisprFlowSrc = final.fetchurl {
            url = "https://github.com/wispr-flow-linux/wispr-flow-linux/releases/download/v${wisprPortVersion}%2Bwispr${wisprAppVersion}/wispr-flow-${wisprFlowVersion}-x86_64.AppImage";
            hash = "sha256-2jeeMDWVnkadE5lyjwb1ThKplYoxp5P/GgZ39OEtiMU=";
          };
          wisprFlowContents = final.appimageTools.extract {
            pname = "wispr-flow";
            version = wisprFlowVersion;
            src = wisprFlowSrc;
          };
        in
        {
          # VSCode extensions
          nix-vscode-extensions = {
            vscode-marketplace = nix-vscode-extensions.extensions.${system}.vscode-marketplace;
            open-vsx = nix-vscode-extensions.extensions.${system}.open-vsx;
          };

          # Use the upstream prebuilt AppImage. The source flake currently needs
          # a separately supplied Windows installer and does not rebuild its
          # native sqlite modules, while the release artifact is complete.
          wispr-flow = final.appimageTools.wrapType2 {
            pname = "wispr-flow";
            version = wisprFlowVersion;
            src = wisprFlowSrc;

            extraPkgs = pkgs: with pkgs; [
              wl-clipboard
              xclip
              xsel
            ];

            extraInstallCommands = ''
              install -Dm444 \
                ${wisprFlowContents}/usr/share/applications/ai.wisprflow.WisprFlow.desktop \
                $out/share/applications/ai.wisprflow.WisprFlow.desktop
              # Electron 42 mis-scales Wispr's onboarding UI under native
              # Wayland on the mixed-scale Niri layout. XWayland keeps one
              # coordinate space; input injection remains handled by uinput.
              substituteInPlace $out/share/applications/ai.wisprflow.WisprFlow.desktop \
                --replace-fail "Exec=AppRun %U" \
                  "Exec=wispr-flow --ozone-platform=x11 %U"

              cp -r ${wisprFlowContents}/usr/share/icons $out/share/

              mkdir -p $out/lib/udev/rules.d
              cat > $out/lib/udev/rules.d/70-wispr-flow-uinput.rules <<'UDEV'
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess", GROUP="input", MODE="0660"
UDEV
            '';

            meta = with final.lib; {
              description = "Unofficial Linux build of Wispr Flow voice dictation";
              homepage = "https://github.com/wispr-flow-linux/wispr-flow-linux";
              license = licenses.unfree;
              mainProgram = "wispr-flow";
              platforms = [ "x86_64-linux" ];
              sourceProvenance = with sourceTypes; [ binaryNativeCode ];
            };
          };
        };
    };
}
