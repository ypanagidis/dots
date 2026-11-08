{
  inputs,
  pkgs,
  lib,
  ...
}:

let
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

  # Keep CLI, niri-ctx and desktop launches on the same backend. A desktop
  # entry alone does not protect bare `discord` launches from NIXOS_OZONE_WL.
  discordLauncher = pkgs.writeShellScriptBin "discord" ''
    unset NIXOS_OZONE_WL
    # Do not exec: the FHS sandbox uses --die-with-parent. Keep this shell
    # alive when a short-lived launcher such as niri-ctx exits after splash.
    # Under XWayland Electron picks scale 2 (the 5K output), so its 800 DIP
    # min width becomes 1600 X px = 1066 logical on the 1.5-scale portrait
    # comms output (960 wide). niri then widens the shared column past the
    # screen and crops Slack/Telegram too. 1.5 is native for HDMI-A-1.
    ${lib.getExe discordWithVulkan} --ozone-platform=x11 --force-device-scale-factor=1.5 "$@"
  '';
  discordDesktop = pkgs.symlinkJoin {
    name = "discord-desktop-${discordWithVulkan.version}";
    paths = [ discordLauncher discordWithVulkan ];
  };

  # Discord plays H.264 videos through Cisco's OpenH264, loaded from the path
  # the host app hardcodes: 2.5.1 (still the case in 1.0.166). Discord's web
  # client now downloads 2.7.0 for calls and deletes every other version on
  # start, so videos fail with "no supported source". This read-only store
  # directory keeps both versions; Discord's cleanup and downloads then fail
  # harmlessly. If the web client moves past 2.7.0, add that version here too.
  discordOpenH264 =
    let
      cisco =
        name: hash:
        pkgs.fetchurl {
          url = "https://ciscobinary.openh264.org/${name}.bz2";
          inherit hash;
        };
    in
    pkgs.runCommand "discord-openh264" { nativeBuildInputs = [ pkgs.bzip2 ]; } ''
      mkdir $out
      bunzip2 -c ${cisco "libopenh264-2.5.1-linux64.7.so" "sha256-guQ224YGQz4/gjx//zJpxDs7o/ElEKhR73sVa4CtGxE="} \
        > $out/libopenh264-2.5.1-linux64.7.so
      bunzip2 -c ${cisco "libopenh264-2.7.0-linux64.8.so" "sha256-RK0N0sWvK6yE0m+J8utOJocIuHOTI9FdM4N/ciHOSYA="} \
        > $out/libopenh264-2.7.0-linux64.8.so
    '';

  # Slack's session cookies are encrypted with a key in KWallet. Electron only
  # picks KWallet when XDG_CURRENT_DESKTOP is KDE; under Hyprland or niri it
  # falls back to an unprotected store, can't decrypt them, and signs out.
  slackKwallet = pkgs.slack.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/slack --add-flags --password-store=kwallet6
    '';
  });
in

{
  # User-facing desktop applications. These do not need to be system packages,
  # so they live in the Home Manager profile.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux (
    with pkgs;
    [
      discordDesktop
      slackKwallet
      telegram-desktop
      libreoffice
      pavucontrol
      remmina
      high-tide
      haruna
      bruno
      obsidian
      wispr-flow
      inputs.opencode-flake.packages.${pkgs.stdenv.hostPlatform.system}.opencode-desktop
    ]
  );

  # Niri's running environment has ~/.local/bin but does not see a newly
  # activated Home Manager profile until the next system activation/login.
  # Keep the comms launch names used by niri-ctx available immediately.
  home.file = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    ".local/bin/discord".source = lib.getExe' discordDesktop "discord";
    ".local/bin/slack".source = lib.getExe slackKwallet;
    ".local/bin/Telegram".source = lib.getExe pkgs.telegram-desktop;
    ".local/bin/telegram-desktop".source = lib.getExe pkgs.telegram-desktop;
    ".config/discord/discord_asset_cache/openh264".source = discordOpenH264;
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
    exec = "${lib.getExe' discordDesktop "discord"} %U";
    terminal = false;
    mimeType = [ "x-scheme-handler/discord" ];
    categories = [
      "Network"
      "InstantMessaging"
    ];
    settings.StartupWMClass = "discord";
  };

  # Sign-in links. Wispr Flow registers a wispr-flow.desktop that doesn't
  # exist, so point its scheme at the packaged entry.
  xdg.mimeApps.defaultApplications = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    "x-scheme-handler/wispr-flow" = "ai.wisprflow.WisprFlow.desktop";
    "x-scheme-handler/slack" = "slack.desktop";
  };
}
