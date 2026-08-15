{
  config,
  inputs,
  lib,
  pkgs,
  dotsLink,
  ...
}:

let
  niriCtx = pkgs.callPackage ../../packages/niri-ctx.nix {
    src = inputs.niri-workspace + "/rust/niri-ctx";
    bashFallback = "${inputs.niri-workspace}/dots/bin/niri-ctx";
  };

  niriPerfLog = pkgs.writeShellApplication {
    name = "niri-perf-log";
    runtimeInputs = with pkgs; [
      coreutils
      procps
    ];
    text = ''
      interval="''${1:-60}"
      case "$interval" in
        *[!0-9]* | 0 | "")
          echo "usage: niri-perf-log [positive-interval-seconds]" >&2
          exit 2
          ;;
      esac

      if ! command -v nvidia-smi >/dev/null; then
        echo "niri-perf-log: nvidia-smi is not available" >&2
        exit 1
      fi

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/niri-perf"
      mkdir -p "$state_dir"
      log="$state_dir/$(date +%Y%m%d-%H%M%S).log"
      echo "logging every ''${interval}s to $log"

      while true; do
        {
          echo "=== $(date --iso-8601=seconds) ==="
          nvidia-smi \
            --query-gpu=driver_version,memory.used,memory.total,utilization.gpu,utilization.memory,pstate,power.draw \
            --format=csv,noheader
          nvidia-smi pmon -s m -c 1
          ps -C niri -C noctalia -C .noctalia-wrapp -C qs -C quickshell -C .quickshell-wra \
            -o pid=,etimes=,rss=,vsz=,comm=,args= --sort=-rss || true
          echo
        } | tee -a "$log"
        sleep "$interval"
      done
    '';
  };
in
{
  # Keep the established dotfiles as the single source of truth, following the
  # same out-of-store-link convention as Ghostty, tmux, and Neovim.
  xdg.configFile."niri".source = dotsLink ".config/niri";

  home.packages = [
    pkgs.noctalia
    niriCtx
    niriPerfLog
  ];

  # Keep a stable command in the first directory on the Niri session PATH.
  # This also makes the v5 shell available to the already-running Niri session
  # before the next system activation updates /etc/profiles/per-user.
  home.file.".local/bin/noctalia".source = lib.getExe pkgs.noctalia;
  home.file.".local/bin/niri-ctx".source = lib.getExe niriCtx;

  # Cargo embeds its sandbox source path in niri-ctx. Point the one operation
  # that still execs the Bash bridge at the copy packaged in the Nix store.
  xdg.configFile."niri-ctx/config.toml".text = ''
    [behavior]
    bash_fallback = "${niriCtx}/libexec/niri-ctx/bash-fallback"
  '';

  # v5 defaults to a floating bar with 100 px gaps at both ends. Match the
  # previous shell's edge-to-edge bar while retaining v5's other defaults.
  xdg.configFile."noctalia/10-bar.toml".text = ''
    [bar.default]
    margin_ends = 0
  '';

  # Catch invalid KDL during Home Manager activation, before the next login.
  home.activation.validateNiriConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.niri}/bin/niri validate --config ${config.xdg.configHome}/niri/config.kdl
  '';
}
