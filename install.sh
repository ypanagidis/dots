#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
NIRI_LINK="$HOME/.config/niri"
HERDR_DIR="$HOME/.config/herdr"
HERDR_CONFIG="$HERDR_DIR/config.toml"
USER_SYSTEMD="$HOME/.config/systemd/user"
UNIT_NAME="niri-ctx-watch.service"
UNIT_SRC="$REPO_ROOT/dots/.config/systemd/user/$UNIT_NAME"
UNIT_DST="$USER_SYSTEMD/$UNIT_NAME"

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

info() {
    printf '%s\n' "$*"
}

# Dispatcher implementation: Rust (default) or Bash (rollback).
#   ./install.sh          -> build + link the Rust dispatcher
#   ./install.sh --bash   -> link the legacy Bash dispatcher (instant rollback)
# The Bash script stays at bin/niri-ctx permanently: it is the rollback
# implementation AND the --tmux-role in-terminal attach path that the Rust
# dispatcher execs (behavior.bash_fallback).
IMPL="rust"
[[ "${1:-}" == "--bash" ]] && IMPL="bash"

RUST_BIN="$REPO_ROOT/rust/niri-ctx/target/release/niri-ctx"

mkdir -p "$LOCAL_BIN"
chmod +x "$REPO_ROOT/dots/bin/niri-ctx"

if [[ "$IMPL" == "rust" ]]; then
    if command -v cargo >/dev/null 2>&1; then
        info "building rust dispatcher..."
        (cd "$REPO_ROOT/rust/niri-ctx" && cargo build --release) || warn "cargo build failed"
    else
        warn "cargo not found; using existing rust binary if present"
    fi
    if [[ -x "$RUST_BIN" ]]; then
        ln -sfn "$RUST_BIN" "$LOCAL_BIN/niri-ctx"
        info "linked $LOCAL_BIN/niri-ctx -> rust dispatcher"
    else
        warn "rust binary missing at $RUST_BIN; falling back to bash dispatcher"
        IMPL="bash"
    fi
fi

if [[ "$IMPL" == "bash" ]]; then
    ln -sfn "$REPO_ROOT/dots/bin/niri-ctx" "$LOCAL_BIN/niri-ctx"
    info "linked $LOCAL_BIN/niri-ctx -> bash dispatcher"
fi

mkdir -p "$HERDR_DIR"
if [[ -e "$HERDR_CONFIG" && ! -L "$HERDR_CONFIG" ]]; then
    herdr_backup="$HERDR_CONFIG.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$HERDR_CONFIG" "$herdr_backup"
    info "backed up $HERDR_CONFIG to $herdr_backup"
fi
ln -sfn "$REPO_ROOT/dots/.config/herdr/config.toml" "$HERDR_CONFIG"
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
    legacy_src="$REPO_ROOT/dots/legacy/niri-scripts/$name"
    installed="$LOCAL_BIN/$name"
    [[ -e "$installed" ]] || continue
    if [[ -f "$legacy_src" ]] && cmp -s "$legacy_src" "$installed"; then
        rm -f "$installed"
        info "removed legacy $installed"
    else
        warn "leaving $installed because it differs from $legacy_src"
    fi
done

# The niri-ctx watch daemon (DP-2 auto-follow) is DISABLED by default per the
# user's 2026-07-04 decision (TOP_FOLLOW=off). The unit file stays in the repo;
# to opt back in: set TOP_FOLLOW in contexts.conf, then
#   ln -sfn "$UNIT_SRC" "$UNIT_DST" && systemctl --user daemon-reload && systemctl --user enable --now niri-ctx-watch
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-enabled "$UNIT_NAME" >/dev/null 2>&1; then
    info "$UNIT_NAME already enabled; leaving it as-is"
fi

if [[ -L "$NIRI_LINK" ]]; then
    niri_target="$(readlink -f "$NIRI_LINK" || true)"
    case "$niri_target" in
        "$REPO_ROOT"/dots/.config/niri|"$REPO_ROOT"/dots/.config/niri/*)
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
    if niri validate -c "$REPO_ROOT/dots/.config/niri/config.kdl"; then
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
