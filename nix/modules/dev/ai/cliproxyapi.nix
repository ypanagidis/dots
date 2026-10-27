{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  # Upstream probes browser availability by opening about:blank, which KIO
  # treats as a missing file. Detect the opener without launching it instead.
  proxy = agents.cli-proxy-api.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./cliproxyapi-browser-probe.patch ];
  });
  stateDir = "${config.xdg.stateHome}/cliproxyapi";
  configPath = "${stateDir}/config.yaml";

  # JSON is valid YAML. Only this credential-free baseline enters the store.
  baseline = pkgs.writeText "cliproxyapi-baseline.json" (
    builtins.toJSON {
      config-version = 8;
      server = {
        host = "127.0.0.1";
        port = 8317;
      };
      management.allow-remote = false;
      oauth.auth-dir = "${stateDir}/auth";
      routing = {
        # Consume one subscription before selecting another available account.
        strategy = "fill-first";
        retry = {
          request-retry = 3;
          max-retry-credentials = 0; # Try the whole pool, not just one backup.
          max-retry-interval = 30;
        };
        cooldown = {
          disable-cooling = false;
          save-cooldown-status = true;
        };
      };
    }
  );

  prepare = pkgs.writeShellApplication {
    name = "cliproxyapi-prepare";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.openssl
      pkgs.util-linux
    ];
    text = ''
      umask 077
      state=${lib.escapeShellArg stateDir}
      mkdir -p "$state/auth"
      chmod 700 "$state" "$state/auth"

      # Login commands and the service can initialize concurrently.
      exec 9>"$state/.prepare.lock"
      flock 9
      for name in api-key management-key; do
        if [ ! -s "$state/$name" ]; then
          openssl rand -hex 32 > "$state/$name"
        fi
        chmod 600 "$state/$name"
      done

      temp=$(mktemp "$state/config.yaml.XXXXXX")
      trap 'rm -f "$temp"' EXIT
      jq --rawfile apiKey "$state/api-key" \
         --rawfile managementKey "$state/management-key" '
        .access["api-keys"] = [($apiKey | rtrimstr("\n"))]
        | .management["secret-key"] = ($managementKey | rtrimstr("\n"))
      ' ${baseline} > "$temp"
      mv -f "$temp" "$state/config.yaml"
    '';
  };

  ensureConfig = ''
    if [ ! -s ${lib.escapeShellArg configPath} ]; then
      ${lib.getExe prepare}
    fi
  '';

  cli = pkgs.writeShellApplication {
    name = "cliproxyapi";
    text = ''
      ${ensureConfig}
      exec ${lib.getExe proxy} -config ${lib.escapeShellArg configPath} "$@"
    '';
  };

  # Cooldowns come from Anthropic's reset headers, so a manual usage reset
  # upstream stays invisible until they expire. Toggling a credential clears
  # its cooldown in the running proxy without a restart.
  resetCooldown = pkgs.writeShellApplication {
    name = "cliproxyapi-reset";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      key=$(<${lib.escapeShellArg "${stateDir}/management-key"})
      api=http://127.0.0.1:8317/v0/management
      call() { curl -fsS -H "Authorization: Bearer $key" "$@"; }

      if [ "$#" -gt 0 ]; then
        names=("$@")
      else
        mapfile -t names < <(call "$api/auth-files" | jq -r '.files[] | select(.next_retry_after != null) | .name')
      fi

      for name in "''${names[@]}"; do
        for disabled in true false; do
          call -X PATCH -H 'Content-Type: application/json' "$api/auth-files/status" \
            -d "$(jq -n --arg name "$name" --argjson disabled "$disabled" '{$name, $disabled}')" >/dev/null
        done
        echo "cleared $name"
      done
    '';
  };

  reconcileCooldown = pkgs.writeShellApplication {
    name = "cliproxyapi-reconcile";
    text = ''
      exec ${lib.getExe pkgs.python3} ${./cliproxyapi-reconcile.py} ${lib.escapeShellArg stateDir}
    '';
  };

  codexProxy = pkgs.writeShellApplication {
    name = "codex-proxy";
    text = ''
      ${ensureConfig}
      CLIPROXYAPI_API_KEY=$(<${lib.escapeShellArg "${stateDir}/api-key"})
      export CLIPROXYAPI_API_KEY
      exec ${lib.getExe agents.codex} \
        -c 'model_provider="cliproxyapi"' \
        -c 'model_providers.cliproxyapi.name="CLIProxyAPI"' \
        -c 'model_providers.cliproxyapi.base_url="http://127.0.0.1:8317/v1"' \
        -c 'model_providers.cliproxyapi.env_key="CLIPROXYAPI_API_KEY"' \
        -c 'model_providers.cliproxyapi.wire_api="responses"' \
        -c 'model_providers.cliproxyapi.requires_openai_auth=false' \
        -c 'model_providers.cliproxyapi.supports_websockets=false' \
        "$@"
    '';
  };

  claudeProxy = pkgs.writeShellApplication {
    name = "claude-proxy";
    text = ''
      ${ensureConfig}
      export ANTHROPIC_BASE_URL=http://127.0.0.1:8317
      ANTHROPIC_AUTH_TOKEN=$(<${lib.escapeShellArg "${stateDir}/api-key"})
      export ANTHROPIC_AUTH_TOKEN
      unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN
      unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
      exec ${lib.getExe agents.claude-code} "$@"
    '';
  };
in
{
  home.packages = [
    proxy
    cli
    resetCooldown
    reconcileCooldown
    codexProxy
    claudeProxy
  ];

  systemd.user.services.cliproxyapi = {
    Unit.Description = "CLIProxyAPI subscription pool";
    Service = {
      Type = "simple";
      ExecStartPre = lib.getExe prepare;
      ExecStart = "${lib.getExe proxy} -config ${configPath}";
      # Allow the first ExecStartPre to create the working directory.
      WorkingDirectory = "-${stateDir}";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Usage resets do not notify the proxy. Recheck only cooling credentials so
  # manual resets recover automatically without retrying exhausted accounts.
  systemd.user.services.cliproxyapi-reconcile = {
    Unit = {
      Description = "Reconcile Claude cooldowns with current subscription usage";
      After = [ "cliproxyapi.service" ];
      Requisite = [ "cliproxyapi.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe reconcileCooldown;
      UMask = "0077";
    };
  };
  systemd.user.timers.cliproxyapi-reconcile = {
    Unit.Description = "Check for manually reset Claude subscriptions";
    Timer = {
      OnStartupSec = "1min";
      OnUnitInactiveSec = "2min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
