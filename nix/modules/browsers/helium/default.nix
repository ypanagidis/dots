{
  pkgs,
  lib,
  inputs,
  ...
}:

{
  imports = [ inputs.helium-flake.homeModules.default ];

  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    programs.helium = {
      enable = true;
      flags = [ ];
      # The flake's wrapper always adds an ozone hint behind a shell
      # expansion, but wrapGAppsHook turns it into a binary wrapper, so
      # Chromium receives the unexpanded `${NIXOS_OZONE_WL:+...}` string as an
      # argument. Drop it and run Helium with no flags.
      package =
        inputs.helium-flake.packages.${pkgs.stdenv.hostPlatform.system}.helium.overrideAttrs
          (
            old:
            let
              ozoneFlag = ''--add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"'';
            in
            {
              preFixup =
                assert lib.assertMsg (lib.hasInfix ozoneFlag old.preFixup)
                  "helium-flake changed its ozone --add-flags line; update the override in helium/default.nix";
                builtins.replaceStrings [ ozoneFlag ] [ "" ] old.preFixup;
            }
          );
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "helium.desktop";
        "x-scheme-handler/http" = "helium.desktop";
        "x-scheme-handler/https" = "helium.desktop";
      };
    };
    # Apps (Wispr Flow, T3 Code, Slack) rewrite mimeapps.list when they
    # register their URL schemes, replacing HM's symlink with a real file. The
    # backup HM makes of it then blocks the next activation, so overwrite it
    # instead; the schemes they care about are declared next to each app.
    xdg.configFile."mimeapps.list".force = true;
  };
}
