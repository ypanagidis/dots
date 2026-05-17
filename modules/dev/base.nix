{
  pkgs,
  pkgsMaster,
  lib,
  ...
}:

{
  # General development CLIs that should be available in normal user shells.
  home.packages =
    (with pkgs; [
      pnpm
      nodejs
      pkgsMaster.codex
      python3
      bun
      httpie
      pscale
      opencode
      playwright-mcp
    ])
    ++ lib.optionals (pkgs ? claude) [ pkgs.claude ];

  # Opencode's MCP config belongs with the opencode package declaration so the
  # package and its runtime integration stay together.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    mcp.playwright = {
      type = "local";
      command = [ "mcp-server-playwright" ];
      enabled = true;
    };
  };
}
