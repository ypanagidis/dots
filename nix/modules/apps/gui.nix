{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;

  # Discord's native Linux monitor capture imports niri's DMA-BUF stream with
  # Vulkan. The nixpkgs FHS wrapper sets the Vulkan ICD path but omits the
  # loader itself, so Discord falls back to SHM, which niri does not expose for
  # full-output capture ("no more input formats"). Keep the FHS environment and
  # add only the missing loader.
  discordWithVulkan = pkgs.discord.override {
    unwrappedDiscord = pkgs.discord.passthru.unwrappedDiscord.overrideAttrs (oldAttrs: {
      passthru = oldAttrs.passthru // {
        targetPkgs = packages: oldAttrs.passthru.targetPkgs packages ++ [ packages.vulkan-loader ];
      };
    });
  };
in

{
  # User-facing desktop applications. These do not need to be system packages,
  # so they live in the Home Manager profile.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux (
    with pkgs;
    [
      discordWithVulkan
      slack
      telegram-desktop
      libreoffice-fresh
      pavucontrol
      remmina
      high-tide
      haruna
      bruno
      obsidian
      inputs.opencode-flake.packages.${pkgs.stdenv.hostPlatform.system}.opencode-desktop
    ]
  );

  # Niri's running environment has ~/.local/bin but does not see a newly
  # activated Home Manager profile until the next system activation/login.
  # Keep the comms launch names used by niri-ctx available immediately.
  home.file = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    ".local/bin/slack".source = lib.getExe pkgs.slack;
    ".local/bin/Telegram".source = lib.getExe pkgs.telegram-desktop;
    ".local/bin/telegram-desktop".source = lib.getExe pkgs.telegram-desktop;
  };

  # Native-Wayland Electron missizes Discord's maximized surface on the
  # rotated portrait ultrawide and crops the right edge — at any output scale
  # (verified live 2026-08-15; neither WaylandPerSurfaceScale/WaylandUiScale
  # nor disabling WaylandFractionalScaleV1 fixed it on Electron 42). XWayland
  # renders it correctly, matching how it worked on the old Arch setup.
  xdg.desktopEntries.discord = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    name = "Discord";
    genericName = "Internet Messenger";
    icon = "discord";
    exec = "env -u NIXOS_OZONE_WL discord --ozone-platform=x11 %U";
    terminal = false;
    mimeType = [ "x-scheme-handler/discord" ];
    categories = [
      "Network"
      "InstantMessaging"
    ];
    settings.StartupWMClass = "discord";
  };
}
