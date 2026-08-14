{ pkgs, ... }:

let
  prismLauncher = pkgs.prismlauncher.override {
    additionalLibs = with pkgs; [
      alsa-lib
      atk
      at-spi2-atk
      cairo
      cups
      dbus
      expat
      glib
      gtk3
      libdrm
      libgbm
      libxkbcommon
      mesa
      nspr
      nss
      pango
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libXtst
      xorg.libxcb
      xorg.libxshmfence
    ];
  };
in

{
  environment.systemPackages = [
    prismLauncher
    (pkgs.writeShellScriptBin "mc-prism" ''
      #!/usr/bin/env bash
      set -euo pipefail

      DEFAULT_INSTANCE="''${MC_PRISM_INSTANCE:-fabric}"
      PRISM_DIR="''${MC_PRISM_DIR:-$HOME/.local/share/PrismLauncher}"
      KSCREEN_DOCTOR_BIN="''${KSCREEN_DOCTOR_BIN:-$(command -v kscreen-doctor || true)}"
      PRISM_LAUNCHER="''${MC_PRISM_LAUNCHER:-${prismLauncher}/bin/prismlauncher}"
      JQ_BIN="''${MC_PRISM_JQ:-${pkgs.jq}/bin/jq}"

      PLAY_WIDTH=3840
      PLAY_HEIGHT=2160
      PLAY_SCALE=1.75
      RESTORE_WIDTH=5120
      RESTORE_HEIGHT=2880
      RESTORE_SCALE=2

      if [ -z "$KSCREEN_DOCTOR_BIN" ]; then
        echo "kscreen-doctor not found in PATH" >&2
        exit 1
      fi

      if [ ! -x "$JQ_BIN" ]; then
        echo "jq not found at $JQ_BIN" >&2
        exit 1
      fi

      SCREEN_JSON="$($KSCREEN_DOCTOR_BIN -j)"

      if [ "$#" -gt 0 ] && [ "''${1#-}" != "$1" ]; then
        LAUNCH_ARGS=("$@")
      else
        INSTANCE_REQUEST="''${1:-$DEFAULT_INSTANCE}"
        if [ -z "$INSTANCE_REQUEST" ]; then
          INSTANCE_REQUEST="$DEFAULT_INSTANCE"
        fi

        resolve_instance_id() {
          local requested="$1"
          local requested_lower
          requested_lower="$(printf "%s" "$requested" | tr '[:upper:]' '[:lower:]')"

          if [ -d "$PRISM_DIR/instances/$requested" ]; then
            echo "$requested"
            return
          fi

          for cfg in "$PRISM_DIR/instances"/*/instance.cfg; do
            [ -f "$cfg" ] || continue

            instance_id="$(basename "$(dirname "$cfg")")"
            instance_name="$(awk -F= '/^name=/{print $2; exit}' "$cfg")"
            instance_name_lower="$(printf "%s" "$instance_name" | tr '[:upper:]' '[:lower:]')"

            if [ "$instance_name_lower" = "$requested_lower" ]; then
              echo "$instance_id"
              return
            fi
          done

          echo "$requested"
        }

        INSTANCE_ID="$(resolve_instance_id "$INSTANCE_REQUEST")"
        LAUNCH_ARGS=(--launch "$INSTANCE_ID")
      fi

      detect_output() {
        printf '%s' "$SCREEN_JSON" | "$JQ_BIN" -r '
          [
            .outputs[]
            | select(.connected == true)
            | select(any(.modes[]?; .size.width == 5120 and .size.height == 2880))
          ][0].name // empty
        '
      }

      detect_mode() {
        local output_name="$1"
        local target_width="$2"
        local target_height="$3"

        printf '%s' "$SCREEN_JSON" | "$JQ_BIN" -r \
          --arg out "$output_name" --argjson w "$target_width" --argjson h "$target_height" '
            .outputs[]
            | select(.name == $out)
            | [.modes[] | select(.size.width == $w and .size.height == $h) | .name][0] // empty
          '
      }

      OUTPUT_NAME="$(detect_output)"

      if [ -z "$OUTPUT_NAME" ] || [ "$OUTPUT_NAME" = "null" ]; then
        OUTPUT_NAME="$(printf '%s' "$SCREEN_JSON" | "$JQ_BIN" -r '
          [
            .outputs[]
            | select(.connected == true)
            | {name: .name, area: (.size.width * .size.height)
          }
          ]
            | sort_by(.area)
            | reverse
            | .[0].name // empty')"

        if [ -z "$OUTPUT_NAME" ] || [ "$OUTPUT_NAME" = "null" ]; then
          echo "No connected output found." >&2
          exit 1
        fi
      fi

      PLAY_MODE="$(detect_mode "$OUTPUT_NAME" "$PLAY_WIDTH" "$PLAY_HEIGHT")"
      RESTORE_MODE="$(detect_mode "$OUTPUT_NAME" "$RESTORE_WIDTH" "$RESTORE_HEIGHT")"

      if [ -z "$PLAY_MODE" ] || [ "$PLAY_MODE" = "null" ]; then
        echo "Could not find $PLAY_WIDTHx$PLAY_HEIGHT mode for $OUTPUT_NAME" >&2
        exit 1
      fi
      if [ -z "$RESTORE_MODE" ] || [ "$RESTORE_MODE" = "null" ]; then
        echo "Could not find $RESTORE_WIDTHx$RESTORE_HEIGHT mode for $OUTPUT_NAME" >&2
        exit 1
      fi

      if [ -z "$PRISM_DIR" ]; then
        echo "PRISM_DIR resolved to empty. Check MC_PRISM_DIR." >&2
        exit 1
      fi

      RESTORE_PENDING=0
      apply_display() {
        local mode="$1"
        local scale="$2"

        if "$KSCREEN_DOCTOR_BIN" "output.$OUTPUT_NAME.mode.$mode" "output.$OUTPUT_NAME.scale.$scale" >/dev/null; then
          return
        fi

        echo "Failed to apply output.$OUTPUT_NAME.mode.$mode scale.$scale" >&2
        return 1
      }

      restore_display() {
        if [ "$RESTORE_PENDING" -eq 0 ]; then
          return
        fi

        if ! apply_display "$RESTORE_MODE" "$RESTORE_SCALE"; then
          echo "Could not restore display. Manual restore may be needed." >&2
        fi
      }

      trap restore_display EXIT INT TERM

      if ! apply_display "$PLAY_MODE" "$PLAY_SCALE"; then
        echo "Failed to apply $PLAY_WIDTH x $PLAY_HEIGHT at $PLAY_SCALE. Restore skipped." >&2
        exit 1
      fi

      RESTORE_PENDING=1

      LAUNCH_STATUS=0
      if command -v gamemoderun >/dev/null 2>&1; then
        gamemoderun "$PRISM_LAUNCHER" "''${LAUNCH_ARGS[@]}" || LAUNCH_STATUS=$?
      else
        "$PRISM_LAUNCHER" "''${LAUNCH_ARGS[@]}" || LAUNCH_STATUS=$?
      fi

      exit "$LAUNCH_STATUS"
    '')

    (pkgs.writeShellScriptBin "mc-shaderpack" ''
            set -euo pipefail

            prism_dir="''${PRISM_DIR:-"$HOME/.local/share/PrismLauncher"}"
            shader_dir="$prism_dir/shaderpacks"

            usage() {
              cat <<'EOF'
      usage:
        mc-shaderpack install <zip-path-or-url>
        mc-shaderpack list
        mc-shaderpack dir
        mc-shaderpack recommended

      notes:
        - shader packs are copied to ~/.local/share/PrismLauncher/shaderpacks
        - set PRISM_DIR to use a custom PrismLauncher directory
      EOF
            }

            ensure_shader_dir() {
              mkdir -p "$shader_dir"
            }

            subcommand="''${1:-}"

            case "$subcommand" in
              install)
                source_input="''${2:-}"
                if [ -z "$source_input" ]; then
                  usage
                  exit 2
                fi

                ensure_shader_dir

                if [[ "$source_input" =~ ^https?:// ]]; then
                  tmp_zip="$(mktemp --suffix=.zip)"
                  trap 'rm -f "$tmp_zip"' EXIT

                  ${pkgs.curl}/bin/curl -fL --retry 3 -o "$tmp_zip" "$source_input"
                  file_name="$(basename "''${source_input%%\?*}")"

                  if [ -z "$file_name" ] || [ "$file_name" = "/" ]; then
                    file_name="shaderpack.zip"
                  fi

                  if [[ "$file_name" != *.zip ]]; then
                    file_name="$file_name.zip"
                  fi

                  cp "$tmp_zip" "$shader_dir/$file_name"
                  echo "Installed $file_name to $shader_dir"
                  exit 0
                fi

                if [ ! -f "$source_input" ]; then
                  echo "File not found: $source_input" >&2
                  exit 1
                fi

                if [[ "$source_input" != *.zip ]]; then
                  echo "Expected a .zip shader pack, got: $source_input" >&2
                  exit 1
                fi

                cp "$source_input" "$shader_dir/"
                echo "Installed $(basename "$source_input") to $shader_dir"
                ;;

              list)
                if [ ! -d "$shader_dir" ]; then
                  echo "No shaderpacks directory yet: $shader_dir"
                  exit 0
                fi

                if [ -z "$(ls -A "$shader_dir")" ]; then
                  echo "No shader packs installed yet."
                  exit 0
                fi

                ls -1 "$shader_dir"
                ;;

              dir)
                ensure_shader_dir
                echo "$shader_dir"
                ;;

              recommended)
                cat <<'EOF'
      Top shader packs (Modrinth):
      - Complementary Reimagined: https://modrinth.com/shader/complementary-reimagined
      - BSL Shaders: https://modrinth.com/shader/bsl-shaders
      - Sildur's Vibrant: https://modrinth.com/shader/sildurs-vibrant-shaders
      - Solas Shader: https://modrinth.com/shader/solas-shader
      EOF
                ;;

              *)
                usage
                exit 2
                ;;
            esac
    '')
  ];
}
