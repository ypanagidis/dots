{
  config,
  pkgs,
  inputs,
  ...
}:

let
  home = config.home.homeDirectory;
  mattPocockSkillsPath = ".agents/skills/mattpocock";

  # All AI coding agents come from the llm-agents flake (numtide binary
  # cache, 160+ packages). Add more by extending this list.
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in

{
  # Everything AI-agent related lives in this module: the agent CLIs plus the
  # per-agent runtime config they need.
  home.packages = with llmAgents; [
    claude-code
    codex
    opencode
    gemini-cli
  ];

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
