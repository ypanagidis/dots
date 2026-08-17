{
  config,
  lib,
  pkgs,
  inputs,
  dotsLink,
  ...
}:

let
  home = config.home.homeDirectory;
  sharedSkillsPath = ".agents/skills";

  # These were installed by earlier experiments. Keep the cleanup explicit so
  # Home Manager never touches Codex's managed .system skills or plugin cache.
  legacySkillPaths = [
    ".codex/skills/agents-sdk"
    ".codex/skills/cloudflare"
    ".codex/skills/cloudflare-email-service"
    ".codex/skills/cloudflare-one"
    ".codex/skills/cloudflare-one-migrations"
    ".codex/skills/durable-objects"
    ".codex/skills/gh-stack"
    ".codex/skills/sandbox-sdk"
    ".codex/skills/turnstile-spin"
    ".codex/skills/web-perf"
    ".codex/skills/workers-best-practices"
    ".codex/skills/wrangler"
    ".pi/agent/skills"
  ];

  # All AI coding agents come from the llm-agents flake (numtide binary
  # cache, 160+ packages). Add more by extending this list.
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in

{
  home.packages = [
    llmAgents.claude-code
    llmAgents.codex
    llmAgents.opencode
    llmAgents.gemini-cli
  ];

  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    skills.paths = [ "${home}/${sharedSkillsPath}" ];
    mcp.playwright = {
      type = "local";
      command = [ "mcp-server-playwright" ];
      enabled = true;
    };
  };

  home.file = {
    # Shared, editable skills. Claude currently discovers only .claude/skills,
    # while the other agents use the canonical .agents tree.
    ".agents/skills".source = dotsLink ".config/agents/skills";
    ".claude/skills".source = dotsLink ".config/agents/skills";
  };

  # Earlier generations created ~/.agents/skills as a real directory containing
  # one Home Manager symlink per skill. Remove it once so the single out-of-store
  # link can take its place; future generations see a symlink and leave it alone.
  home.activation.migrateAgentSkillsRoot = config.lib.dag.entryBefore [ "checkLinkTargets" ] ''
    skillsRoot=${lib.escapeShellArg "${home}/${sharedSkillsPath}"}
    if [ -d "$skillsRoot" ] && [ ! -L "$skillsRoot" ]; then
      rm -r -- "$skillsRoot"
    fi
  '';

  # Remove only known legacy skill installs outside the canonical shared tree.
  home.activation.removeLegacyAgentSkills = config.lib.dag.entryBefore [ "checkLinkTargets" ] (
    lib.concatMapStringsSep "\n" (relativePath: ''
      target=${lib.escapeShellArg "${home}/${relativePath}"}
      if [ -L "$target" ]; then
        rm -- "$target"
      elif [ -d "$target" ]; then
        rm -r -- "$target"
      fi
    '') legacySkillPaths
  );
}
