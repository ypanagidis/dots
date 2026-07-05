# Niri Developer Workflow

This setup is driven by one dispatcher:

```sh
/home/yiannis/.local/bin/niri-ctx
```

Since 2026-07-05 that is a symlink to the **Rust dispatcher**
(`rust/niri-ctx/target/release/niri-ctx`, built by `install.sh`). The original
Bash implementation stays at `bin/niri-ctx`: it is the instant rollback
(`./install.sh --bash`) and still owns the in-terminal session attach
(`--tmux-role`), which the Rust dispatcher execs.

The niri config lives in this repo, and `~/.config/niri` is expected to point
here. Project-specific settings are in `.config/niri/contexts.conf` — the Rust
dispatcher derives its config from it live (plus optional Rust-only overrides
in `~/.config/niri-ctx/config.toml`), so one file drives both implementations.
Keybindings call `niri-ctx`; window rules handle stable placement.

## The mental model

- `DP-1` (main): the **context carousel** — one workspace per job/project.
- `DP-2` (top): ambient (`top-ambient`, Spotify) or a context's devtools.
- `HDMI-A-1` (vertical): static comms — Slack, Telegram, Discord.
- A context = **two full-screen-ish cards**: docs browser (column 1) + one
  work terminal (column 2). Editor/agents/logs live INSIDE the work terminal
  as herdr tabs, one herdr workspace per repo. An output browser is on-demand.

## Monitors and startup

- `DP-1`: 5120x2880, main work display.
- `DP-2`: top display for `top-ambient` and per-context devtools workspaces.
- `HDMI-A-1`: rotated comms display.

Autostart runs `niri-ctx startup`, which waits until niri has the `UP`
workspace on `DP-1`, then focuses it without triggering workspace
back-and-forth.

## Workspaces

`DP-1`: `scratch`, `Webroot`, `UP`, `Sealant`, `Side`, `Admin`
`DP-2`: `top-ambient`, `UP-devtools`, `Webroot-devtools`, `Sealant-devtools`, `Side-devtools`
`HDMI-A-1`: `comms`

`Admin` deliberately has no devtools workspace. `scratch` is a pseudo-context:
helium plus a plain terminal, no herdr session.

## Hotkeys

Hyper on this keyboard emits `CTRL+ALT+Shift+Super`.

- `Hyper+1`: `niri-ctx scratch`
- `Hyper+2`: `niri-ctx open Webroot`
- `Hyper+3`: `niri-ctx open UP`
- `Hyper+4`: `niri-ctx open Sealant`
- `Hyper+5`: `niri-ctx open Side`
- `Hyper+6`: `niri-ctx open Admin`
- `Hyper+A`: `niri-ctx open current docs`
- `Hyper+G`: `niri-ctx open current editor`
- `Hyper+C`: `niri-ctx open current agents`
- `Hyper+R`: `niri-ctx open current agents` (duplicate of `Hyper+C`, kept deliberately for now)
- `Hyper+T`: `niri-ctx spotify`
- `Hyper+Escape`: `niri-ctx top-ambient`
- `Hyper+V`: `niri-ctx comms`
- `Hyper+D`: `niri-ctx devtools-here`
- `Hyper+Left/Right` (`H`/`L`): focus previous/next card.
- `Hyper+Up/Down` (`K`/`J`): focus workspace above/below.
- `Hyper+[` / `Hyper+]`: focus monitor left/right; `Hyper+Page_Up/Down` up/down.

Layout controls on `Mod`: `Mod+Ctrl+R` preset widths, `Mod+Ctrl+M` maximize
column, `Mod+M` maximize to edges, `Mod+Shift+M` fullscreen, `Mod+W` tabbed
column.

## Dispatcher commands

```sh
niri-ctx open <UP|Webroot|Sealant|Side|Admin|current> [all|docs|output|editor|agents|logs|term|repo:<label>]
niri-ctx scratch
niri-ctx comms
niri-ctx spotify
niri-ctx top-ambient
niri-ctx devtools-here
niri-ctx startup
niri-ctx watch
niri-ctx doctor [--json]
niri-ctx --tmux-role <ctx> <role>       # internal: in-terminal session attach

# New with the Rust dispatcher:
niri-ctx current                        # print the inferred context
niri-ctx inspect [--json]               # dump desktop state + resolved config
niri-ctx plan <command...>              # show what a command WOULD do
niri-ctx --dry-run <command...>         # same, for any mutating command
niri-ctx init-config                    # freeze derived config to config.toml
```

Context aliases: `job1`→UP, `job2`→Webroot, `side1`→Sealant, `side2`→Side
(case-insensitive). `current` is inferred from the focused workspace
(`-devtools` suffix stripped), falling back to the active workspace on `DP-1`.

Every command **converges**: it drives the desktop to the canonical state from
any starting layout (verified by `tests/converge.sh`). Running a command twice
is always safe; a settled state plans zero actions.

## Cards and placement

`niri-ctx open <ctx>` guarantees: docs browser at column 1, work terminal at
column 2, both on the context workspace, focus ending on the docs card.
Drifted cards are moved back; stacked cards are expelled apart.

Work terminals carry app-id `dev.yiannis.niri.<slug>.work` (scratch:
`dev.yiannis.niri.scratch.term`); rules.kdl places them declaratively (rules
still also match the legacy per-role ids for old windows). Comms apps are
matched by anchored app IDs: Slack `slack`, Discord `discord`, Telegram
`org.telegram.desktop`. Spotify is `Spotify` and lives on `top-ambient`.

Browser cards are tracked by cache files under
`${XDG_CACHE_HOME:-$HOME/.cache}/niri-ctx/` (window id + compositor socket;
entries are invalidated on compositor restart or window death, and a fresh
card is spawned and re-cached automatically).

## Terminal sessions (herdr, repo-major)

Each context has ONE herdr session, `<Ctx>-work`. Inside it:

- one herdr **workspace per repo** (from `CTX_REPOS`, first entry = default),
- tabs `editor` / `agents` / `logs` in that order inside each repo workspace,
  so `prefix+1/2/3` is uniform everywhere,
- the editor tab runs `nvim`.

Role deep-links (`open <ctx> agents` etc.) act on the currently focused repo
workspace, falling back to the default repo; `open <ctx> repo:<label>`
focuses/creates a repo workspace. `Admin` is one plain `term` workspace.

tmux is the invisible fallback (`SESSION_BACKEND="tmux"` to force): same
session name, windows named `<repo>/<role>`.

Herdr keys: `Ctrl+S` prefix; `prefix+d` detach, `prefix+v`/`prefix+-` splits,
`prefix+m` zoom, `prefix+u` scrollback, `prefix+c` new tab, `prefix+1..9`
switch tab, `prefix+h/j/k/l` pane focus.

## contexts.conf

Source of truth for repos, profiles, outputs, terminal, backend, top-follow:

```bash
CTX_REPOS[UP]="mono=$HOME/Developer/Work/UP/mono"
CTX_REPOS[Webroot]="webroot=$HOME/Developer/Work/Webroot"
CTX_REPOS[Sealant]="core=$HOME/Developer/OSS/Sealant/Core sealantd=$HOME/Developer/OSS/Sealant/Sealantd"
CTX_REPOS[Side]="sandbox=$HOME/Developer/sandbox"
CTX_REPOS[Admin]="term=$HOME"

CTX_HELIUM_PROFILE=( [UP]="Profile 1" [Webroot]="Profile 3" ... )

MAIN_OUTPUT="DP-1"  TOP_OUTPUT="DP-2"  COMMS_OUTPUT="HDMI-A-1"
HELIUM_BIN="${HELIUM_BIN:-/opt/helium-browser-bin/helium}"
CONTEXT_TERMINAL="${NIRI_CONTEXT_TERMINAL:-ghostty}"
SESSION_BACKEND="herdr"
TOP_FOLLOW="off"
```

Paths in `CTX_REPOS` must not contain spaces. Labels are lowercase
`[a-z0-9_-]+`.

## Comms

`Hyper+V` / `niri-ctx comms`: opens missing Slack/Telegram/Discord, moves them
to `comms`, orders them Slack, Telegram, Discord and stacks them into one
full-width column with roughly equal heights (best effort — niri layout
constraints apply).

## DevTools / top display

Frontend mode was removed (2026-07-04). Focus a window and press `Hyper+D`
(`devtools-here`) to send it to the current context's devtools workspace on
`DP-2`; `Hyper+Escape` returns `DP-2` to `top-ambient`. Focus always comes
back to `DP-1`.

`DP-2` does NOT follow focus automatically: `TOP_FOLLOW="off"` and the
`niri-ctx-watch.service` unit is disabled; `install.sh` never enables it.
The Rust watcher exists (`niri-ctx watch`, see `WATCHER_DESIGN.md`) for
opting back in: set `TOP_FOLLOW` to `devtools` or `ambient`, then link and
enable the unit per the comments in `install.sh`.

## Health and debugging

```sh
niri-ctx doctor          # full environment check
niri-ctx current         # which context am I in?
niri-ctx inspect --json  # what does the dispatcher see?
niri-ctx plan open UP    # what WOULD it do?
```

The dispatcher logs every invocation and executed action to
`${XDG_CACHE_HOME:-$HOME/.cache}/niri-ctx/log` (Bash and Rust share the file).
`--verbose` adds detail on stderr.

Launch failures are loud: if a terminal process dies, the error reports the
exit code; if it stays alive but its window never maps (the ghostty/VRAM
mode), the error says exactly that, and the dispatcher self-heals once
(kill by class marker + retry) before reporting.

If a card opens on the wrong workspace: `niri msg pick-window` to verify the
app ID, `niri validate -c ~/.config/niri/config.kdl`, then check the log.
If a browser card focuses the wrong window: `niri-ctx doctor`, then remove the
stale cache entry only after confirming the window is gone.
If terminal sessions misbehave: `SESSION_BACKEND="tmux"` bypasses herdr.

## Rollback

```sh
./install.sh --bash    # relink ~/.local/bin/niri-ctx to the Bash dispatcher
./install.sh           # back to Rust
```

`tests/converge.sh` verifies either implementation live
(`NIRI_CTX=<path> ./tests/converge.sh`, 24 assertions).
