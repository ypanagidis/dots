{
  config,
  pkgs,
  pkgsMaster,
  lib,
  inputs,
  ...
}:

let
  home = config.home.homeDirectory;
  mattPocockSkillsPath = ".agents/skills/mattpocock";
in

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
      graphite-cli
      opencode
      playwright-mcp
    ])
    ++ lib.optionals (pkgs ? claude) [ pkgs.claude ];

  # Opencode's MCP config belongs with the opencode package declaration so the
  # package and its runtime integration stay together.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    skills.paths = [ "${home}/${mattPocockSkillsPath}" ];
    mcp.playwright = {
      type = "local";
      command = [ "mcp-server-playwright" ];
      enabled = true;
    };
  };

  # Codex discovers user skills from ~/.agents/skills. OpenCode also scans this
  # location, and the explicit path above keeps the shared upstream tree visible.
  home.file.${mattPocockSkillsPath}.source = "${inputs.mattpocock-skills}/skills";
}
