#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
NIRI_LINK="$HOME/.config/niri"
HERDR_DIR="$HOME/.config/herdr"
HERDR_CONFIG="$HERDR_DIR/config.toml"
USER_SYSTEMD="$HOME/.config/systemd/user"
UNIT_NAME="niri-ctx-watch.service"
UNIT_SRC="$REPO_ROOT/.config/systemd/user/$UNIT_NAME"
UNIT_DST="$USER_SYSTEMD/$UNIT_NAME"

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

info() {
    printf '%s\n' "$*"
}

mkdir -p "$LOCAL_BIN"
chmod +x "$REPO_ROOT/bin/niri-ctx"
ln -sfn "$REPO_ROOT/bin/niri-ctx" "$LOCAL_BIN/niri-ctx"
info "linked $LOCAL_BIN/niri-ctx"

mkdir -p "$HERDR_DIR"
if [[ -e "$HERDR_CONFIG" && ! -L "$HERDR_CONFIG" ]]; then
    herdr_backup="$HERDR_CONFIG.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$HERDR_CONFIG" "$herdr_backup"
    info "backed up $HERDR_CONFIG to $herdr_backup"
fi
ln -sfn "$REPO_ROOT/.config/herdr/config.toml" "$HERDR_CONFIG"
info "linked $HERDR_CONFIG"
if command -v herdr >/dev/null 2>&1 && pgrep -u "$(id -u)" -x herdr >/dev/null 2>&1; then
    timeout 5 herdr server reload-config >/dev/null 2>&1 || true
fi

legacy_names=(
    niri-frontend-mode
    niri-layout-comms
    niri-move-focused-devtools
    niri-open-context
    niri-open-spotify
    niri-smart-column-left
    niri-smart-column-right
    niri-top-ambient
)

for name in "${legacy_names[@]}"; do
    legacy_src="$REPO_ROOT/legacy/niri-scripts/$name"
    installed="$LOCAL_BIN/$name"
    [[ -e "$installed" ]] || continue
    if [[ -f "$legacy_src" ]] && cmp -s "$legacy_src" "$installed"; then
        rm -f "$installed"
        info "removed legacy $installed"
    else
        warn "leaving $installed because it differs from $legacy_src"
    fi
done

mkdir -p "$USER_SYSTEMD"
if [[ -e "$UNIT_SRC" ]]; then
    ln -sfn "$UNIT_SRC" "$UNIT_DST"
    info "linked $UNIT_DST"
else
    warn "systemd unit not present yet: $UNIT_SRC"
fi

if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user daemon-reload; then
        info "systemd user daemon reloaded"
    else
        warn "systemctl --user daemon-reload failed"
    fi
    if [[ -e "$UNIT_DST" ]]; then
        if systemctl --user enable --now "$UNIT_NAME"; then
            info "enabled $UNIT_NAME"
        else
            warn "could not enable/start $UNIT_NAME outside an active user session"
        fi
    fi
else
    warn "systemctl not found"
fi

if [[ -L "$NIRI_LINK" ]]; then
    niri_target="$(readlink -f "$NIRI_LINK" || true)"
    case "$niri_target" in
        "$REPO_ROOT"/.config/niri|"$REPO_ROOT"/.config/niri/*)
            info "$NIRI_LINK points into repo"
            ;;
        *)
            warn "$NIRI_LINK points to ${niri_target:-unknown}, not into $REPO_ROOT"
            ;;
    esac
else
    warn "$NIRI_LINK is not a symlink into the repo"
fi

if command -v niri >/dev/null 2>&1; then
    if niri validate -c "$REPO_ROOT/.config/niri/config.kdl"; then
        info "niri validate passed"
    else
        warn "niri validate failed"
    fi
else
    warn "niri not found; skipped validate"
fi

if "$LOCAL_BIN/niri-ctx" doctor; then
    info "niri-ctx doctor passed"
else
    warn "niri-ctx doctor reported failures"
fi

info "install complete"
