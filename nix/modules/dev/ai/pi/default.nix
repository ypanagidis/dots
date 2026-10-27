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

  # Upstream 0.60.3 predates Astra and rejects /fast for gpt-6-astra even
  # though Codex advertises its priority tier. Keep this patch beside the pin
  # until @narumitw/pi-usage includes Astra itself.
  piUsage = pkgs.runCommand "pi-usage-0.60.3-astra" { } ''
    cp -R ${piNodeModules}/node_modules/@narumitw/pi-usage "$out"
    chmod -R u+w "$out"

    substituteInPlace "$out/src/codex-fast.ts" \
      --replace-fail $'\t"gpt-5.4",' $'\t"gpt-6-astra",\n\t"gpt-5.4",'
    substituteInPlace "$out/dist/index.ts" \
      --replace-fail $'  "gpt-5.4",' $'  "gpt-6-astra",\n  "gpt-5.4",'

    ln -s ${piNodeModules}/node_modules "$out/node_modules"
  '';

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
    packages = [
      "npm:@plannotator/pi-extension@0.27.3"
      piUsage
      "npm:pi-atomic-images@0.2.0"
      {
        source = "npm:pi-lens@4.0.1";
        extensions = [ ];
        skills = [ ];
      }
      "npm:pi-web-access@0.23.0"
    ];
  };
  piSettingsBaseline = pkgs.writeText "pi-settings.json" (builtins.toJSON piSettings);

  # Executor runs on mendbox (hosts/executor); this machine is only a client.
  # The bearer token lives outside the store in ~/.config/executor/token.
  executorOrigin = "https://executor.tailc79e49.ts.net";
  executorToken = "${home}/.config/executor/token";
  executorCli = pkgs.writeShellScriptBin "executor" ''
    token="$(cat ${lib.escapeShellArg executorToken})"
    # Upstream `open` only finds local daemons; the web UI signs in from ?_token.
    if [ "''${1-}" = open ]; then
      exec ${pkgs.xdg-utils}/bin/xdg-open "${executorOrigin}/?_token=$token"
    fi
    EXECUTOR_AUTH_TOKEN="$token" exec ${pkgs.callPackage ../../../../pkgs/executor.nix { }}/bin/executor "$@"
  '';

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
    executorCli
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
    # Default server profile for `executor call`/`tools`; without it the CLI
    # would start an empty local daemon.
    ".executor/server-connections.json".text = builtins.toJSON {
      version = 1;
      defaultProfile = "mendbox";
      profiles = [
        {
          name = "mendbox";
          connection = {
            kind = "http";
            key = "profile:mendbox";
            origin = executorOrigin;
            apiBaseUrl = "${executorOrigin}/api";
            displayName = "mendbox";
          };
        }
      ];
    };
    ".pi/agent/mcp.json".text = builtins.toJSON {
      settings = {
        hostConfigDiscovery = "off";
        mcpFooterStatus = "compact";
        notifyOnStartupConnect = false;
        scriptMode = false;
        disableProxyTool = true;
      };
      mcpServers.executor = {
        url = "${executorOrigin}/mcp";
        auth = "bearer";
        bearerToken = "!cat ${lib.escapeShellArg executorToken}";
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
        | del(."pi-codex-fast")
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
}
