{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  home = config.home.homeDirectory;
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Extensions share one pinned production dependency graph. Their source,
  # local fixes, and this lock all live together in the repository.
  piNodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ./.;
    nodejs = pkgs.nodejs;
    derivationArgs.npmFlags = [ "--legacy-peer-deps" ];
  };

  piRuntime = pkgs.runCommand "yiannis-pi-runtime" { } ''
    mkdir -p "$out"
    cp -R ${./extensions} "$out/extensions"
    cp -R ${./themes} "$out/themes"
    ln -s ${piNodeModules}/node_modules "$out/node_modules"
  '';

  # Pi and its extensions update settings.json at runtime. Nix supplies the
  # baseline while preserving interactive choices such as thinking and speed.
  piSettings = {
    theme = "github-dark-default";
    defaultProjectTrust = "ask";
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-sol";
    enableSkillCommands = true;
    "pi-codex-fast".mode = "fast";
    packages = [
      "npm:@plannotator/pi-extension@0.27.3"
      "npm:@calesennett/pi-codex-fast@0.1.6"
      {
        source = "npm:pi-lens@4.0.1";
        extensions = [ ];
        skills = [ ];
      }
      "npm:pi-web-access@0.23.0"
    ];
  };
  piSettingsBaseline = pkgs.writeText "pi-settings.json" (builtins.toJSON piSettings);

  # Executor's Bun executable must remain unpatched: its program is appended
  # to the binary. nix-ld supplies the libraries expected by upstream.
  executor = pkgs.stdenvNoCC.mkDerivation {
    pname = "executor";
    version = "1.5.40";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/executor/-/executor-1.5.40-linux-x64.tgz";
      hash = "sha256-kXwYuO5eB4hxHewtcYztGlZS+DxzdcHXjBjNxgeGOVI=";
    };
    sourceRoot = "package";
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/lib/executor"
      cp -R bin/. "$out/lib/executor/"
      ln -s ../lib/executor/executor "$out/bin/executor"
      runHook postInstall
    '';
    meta = {
      description = "Local integration gateway for AI agents";
      homepage = "https://executor.sh";
      license = lib.licenses.mit;
      mainProgram = "executor";
      platforms = [ "x86_64-linux" ];
    };
  };

  # Plannotator includes node-pty and installs into Pi's writable package cache.
  pi = pkgs.symlinkJoin {
    name = "pi-with-native-extension-build-support";
    paths = [ llmAgents.pi ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/pi" \
        --set PI_WORKFLOW_NODE ${pkgs.nodejs}/bin/node \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.gnumake
            pkgs.stdenv.cc
            pkgs.python3
          ]
        }
    '';
  };
in

{
  home.packages = [
    pi
    executor
    # Use nixpkgs' wrapped Marksman instead of Pi Lens' upstream binary, whose
    # bundled .NET runtime aborts on NixOS when it cannot find ICU.
    pkgs.marksman
  ];

  home.file = {
    ".pi/agent/extensions".source = "${piRuntime}/extensions";
    # Bun resolves imports from Home Manager's visible symlink path rather than
    # the extension's real store path, so dependencies must be visible here.
    ".pi/agent/node_modules".source = "${piRuntime}/node_modules";
    ".pi/agent/themes".source = "${piRuntime}/themes";
    ".pi/agent/mcp.json".text = builtins.toJSON {
      settings = {
        hostConfigDiscovery = "off";
        mcpFooterStatus = "compact";
        notifyOnStartupConnect = false;
        scriptMode = false;
        disableProxyTool = true;
      };
      mcpServers.executor = {
        command = "${executor}/bin/executor";
        args = [
          "mcp"
          "--elicitation-mode"
          "model"
        ];
        lifecycle = "keep-alive";
        protocolVersion = "auto";
        requestTimeoutMs = 120000;
        directTools = true;
        toolPrefix = "none";
      };
    };
  };

  # The live file must be writable. Runtime values win across rebuilds, except
  # for the declarative package list and its version pins.
  home.activation.writeMutablePiSettings = config.lib.dag.entryAfter [ "linkGeneration" ] ''
    settingsDir=${lib.escapeShellArg "${home}/.pi/agent"}
    settingsFile="$settingsDir/settings.json"
    baseline=${lib.escapeShellArg piSettingsBaseline}

    mkdir -p "$settingsDir"
    temp="$(${pkgs.coreutils}/bin/mktemp "$settingsDir/.settings.json.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$temp"' EXIT

    if [ -e "$settingsFile" ] \
      && ${pkgs.jq}/bin/jq -e 'type == "object"' "$settingsFile" >/dev/null 2>&1
    then
      ${pkgs.jq}/bin/jq --slurpfile current "$settingsFile" '
        . as $baseline
        | ($current[0] // {}) as $runtime
        | ($baseline * $runtime)
        | .packages = $baseline.packages
      ' "$baseline" > "$temp"
    else
      ${pkgs.coreutils}/bin/cp "$baseline" "$temp"
    fi

    ${pkgs.coreutils}/bin/chmod 0600 "$temp"
    ${pkgs.coreutils}/bin/rm -f "$settingsFile"
    ${pkgs.coreutils}/bin/mv "$temp" "$settingsFile"
    trap - EXIT
  '';

  systemd.user.services.executor = {
    Unit.Description = "Executor integration gateway";
    Service = {
      Type = "simple";
      ExecStart = "${executor}/bin/executor daemon run --foreground --hostname 127.0.0.1 --port 4788";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
      Environment = [
        "HOME=${home}"
        "DO_NOT_TRACK=1"
        "EXECUTOR_DISABLE_ANALYTICS=1"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
