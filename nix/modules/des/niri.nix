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
      gawk
      jq
      procps
    ];
    text = ''
      sample_interval="''${1:-1}"
      case "$sample_interval" in
        *[!0-9]* | 0 | "")
          echo "usage: niri-perf-log [positive-interval-seconds]" >&2
          exit 2
          ;;
      esac

      nvidia_smi=/run/current-system/sw/bin/nvidia-smi
      if [[ ! -x "$nvidia_smi" ]]; then
        echo "niri-perf-log: nvidia-smi is not available" >&2
        exit 1
      fi

      perf_state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/niri-perf"
      mkdir -p "$perf_state_dir"
      perf_log="$perf_state_dir/$(date +%Y%m%d-%H%M%S).log"
      previous_pid=""
      previous_vram=""
      high_water_vram=0

      write_event() {
        event_name="$1"
        event_pid="$2"
        event_previous="$3"
        event_current="$4"
        event_pmon="$5"

        if (( event_current > high_water_vram )); then
          high_water_vram="$event_current"
        fi

        event_delta=0
        if [[ "$event_previous" =~ ^[0-9]+$ ]]; then
          event_delta=$((event_current - event_previous))
        fi

        {
          echo "=== $(date --iso-8601=seconds) event=$event_name pid=$event_pid previous_mib=$event_previous current_mib=$event_current delta_mib=$event_delta high_water_mib=$high_water_vram ==="
          "$nvidia_smi" \
            --query-gpu=driver_version,memory.used,memory.total,utilization.gpu,utilization.memory,pstate,power.draw \
            --format=csv,noheader
          printf '%s\n' "$event_pmon"
          ps -C niri -C noctalia -C .noctalia-wrapp -C qs -C quickshell -C .quickshell-wra \
            -o pid=,etimes=,rss=,vsz=,comm=,args= --sort=-rss || true
          if command -v niri >/dev/null; then
            niri msg -j windows 2>/dev/null \
              | jq -c '{window_count: length, focused: [.[] | select(.is_focused) | {id, app_id, title, workspace_id, layout}], apps: [.[].app_id]}' \
              || true
          fi
          echo
        } | tee -a "$perf_log"
      }

      echo "watching Niri VRAM every ''${sample_interval}s; events: $perf_log"

      while true; do
        current_pid="$(pgrep -xo niri || true)"
        if [[ -z "$current_pid" ]]; then
          previous_pid=""
          previous_vram=""
          sleep "$sample_interval"
          continue
        fi

        pmon_snapshot="$("$nvidia_smi" pmon -s m -c 1)"
        current_vram="$(
          awk -v pid="$current_pid" '$2 == pid && $4 ~ /^[0-9]+$/ { print $4; exit }' \
            <<< "$pmon_snapshot"
        )"
        if [[ -z "$current_vram" ]]; then
          sleep "$sample_interval"
          continue
        fi

        if [[ "$current_pid" != "$previous_pid" || -z "$previous_vram" ]]; then
          previous_pid="$current_pid"
          previous_vram="$current_vram"
          high_water_vram="$current_vram"
          write_event "BASELINE" "$current_pid" "none" "$current_vram" "$pmon_snapshot"
        elif (( current_vram > previous_vram )); then
          write_event "INCREASE" "$current_pid" "$previous_vram" "$current_vram" "$pmon_snapshot"
          previous_vram="$current_vram"
        elif (( current_vram < previous_vram )); then
          write_event "DECREASE" "$current_pid" "$previous_vram" "$current_vram" "$pmon_snapshot"
          previous_vram="$current_vram"
        fi

        sleep "$sample_interval"
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

  # Sample Niri's per-process VRAM once a second and persist only changes. By
  # binding this service to niri.service, KDE sessions never start the logger.
  systemd.user.services.niri-vram-log = {
    Unit = {
      Description = "Log Niri VRAM changes";
      After = [ "niri.service" ];
      PartOf = [ "niri.service" ];
    };
    Service = {
      ExecStart = "${lib.getExe niriPerfLog} 1";
      Restart = "on-failure";
      RestartSec = 2;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    Install.WantedBy = [ "niri.service" ];
  };

  # Cargo embeds its sandbox source path in niri-ctx. Point the one operation
  # that still execs the Bash bridge at the copy packaged in the Nix store.
  xdg.configFile."niri-ctx/config.toml".text = ''
    [behavior]
    bash_fallback = "${niriCtx}/libexec/niri-ctx/bash-fallback"

    [terminal]
    program = "alacritty"
  '';

  # Keep the v5 bar edge-to-edge, matching the previous shell. The clock sits
  # in the status section in place of the network widget.
  xdg.configFile."noctalia/10-bar.toml".text = ''
    [bar.default]
    margin_ends = 0
    smart_auto_hide = true
    reserve_space = false
    center = []
    end = ["media", "tray", "notifications", "clipboard", "clock", "bluetooth", "volume", "brightness", "battery", "control-center", "session"]

    [bar.default.monitor.dell_27]
    match = "DP-2"
    smart_auto_hide = false
    reserve_space = true
  '';

  # Catch invalid KDL during Home Manager activation, before the next login.
  home.activation.validateNiriConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.niri}/bin/niri validate --config ${config.xdg.configHome}/niri/config.kdl
  '';
}
