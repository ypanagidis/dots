# Niri Developer Workflow

This setup is driven by one dispatcher:

```sh
/home/yiannis/.local/bin/niri-ctx
```

The niri config lives in this repo, and `~/.config/niri` is expected to point here. Project-specific settings are in `.config/niri/contexts.conf`; keybindings call `niri-ctx`, while window rules handle stable placement.

## Monitors

- `DP-1`: main work display.
- `DP-2`: top display for `top-ambient` and project DevTools workspaces.
- `HDMI-A-1`: comms display.

Startup runs:

```sh
niri-ctx startup
```

That waits until niri has the `UP` workspace on `DP-1`, then focuses it without triggering workspace back-and-forth.

## Workspaces

Project workspaces on `DP-1`:

- `UP`
- `Webroot`
- `Sealant`
- `Side`
- `Admin`

Top workspaces on `DP-2`:

- `top-ambient`
- `UP-devtools`
- `Webroot-devtools`
- `Sealant-devtools`
- `Side-devtools`

Comms workspace on `HDMI-A-1`:

- `comms`

## Hotkeys

Hyper on this keyboard emits `CTRL+ALT+Shift+Super`. Because Shift is already part of Hyper, `Hyper+Shift+...` is not a distinct binding shape.

- `Hyper+1`: `niri-ctx open UP`
- `Hyper+2`: `niri-ctx open Webroot`
- `Hyper+3`: `niri-ctx open Sealant`
- `Hyper+4`: `niri-ctx open Side`
- `Hyper+5`: `niri-ctx open Admin`
- `Hyper+A`: `niri-ctx open current docs`
- `Hyper+G`: `niri-ctx open current editor`
- `Hyper+C`: `niri-ctx open current agents`
- `Hyper+R`: `niri-ctx open current agents` (same as `Hyper+C`; the `term` role exists but is unbound)
- `Hyper+T`: `niri-ctx spotify`
- `Hyper+Escape`: `niri-ctx top-ambient`
- `Hyper+V`: `niri-ctx comms`
- `Hyper+D`: `niri-ctx devtools-here`
- `Hyper+Left` / `Hyper+H`: focus previous card.
- `Hyper+Right` / `Hyper+L`: focus next card.
- `Hyper+Up` / `Hyper+K`: focus workspace above.
- `Hyper+Down` / `Hyper+J`: focus workspace below.
- `Hyper+[` / `Hyper+]`: focus monitor left/right.
- `Hyper+Page_Up` / `Hyper+Page_Down`: focus monitor up/down.

Layout controls that remain on `Mod`:

- `Mod+Ctrl+R`: cycle preset column widths.
- `Mod+Ctrl+M`: maximize column.
- `Mod+M`: maximize window to edges.
- `Mod+Shift+M`: fullscreen window.
- `Mod+W`: toggle tabbed column display.

## Card Order

`niri-ctx open <context>` guarantees the project card order after it has created or found the required windows:

1. Docs browser
2. Editor terminal
3. Agents terminal
4. Output browser
5. Logs terminal

`Admin` is smaller and opens docs plus a normal terminal. The dispatcher orders columns by window id after all target cards exist; it does not rely on spawn timing. Focus ends on the project workspace on `DP-1`, with the docs browser focused for full context opens.

## Window Placement

Project terminals are placed declaratively by app-id rules. The dispatcher starts terminals with app IDs like:

```text
dev.yiannis.niri.up.editor
dev.yiannis.niri.webroot.agents
dev.yiannis.niri.sealant.logs
dev.yiannis.niri.side.term
dev.yiannis.niri.admin.term
```

Rules match `dev.yiannis.niri.<slug>.(editor|agents|logs|term)` and open those windows on the matching project workspace. The script then focuses the window by id.

Comms apps are matched by anchored app IDs:

- Slack: `slack`
- Discord: `discord`
- Telegram: `org.telegram.desktop`

Spotify is matched as `Spotify` and opens on `top-ambient`.

## Dispatcher Commands

Supported `niri-ctx` commands:

```sh
niri-ctx open <UP|Webroot|Sealant|Side|Admin|current> [all|docs|output|editor|agents|logs|term]
niri-ctx comms
niri-ctx devtools-here
niri-ctx top-ambient
niri-ctx spotify
niri-ctx watch
niri-ctx startup
niri-ctx doctor
niri-ctx --tmux-role <ctx> <role>
```

`current` is inferred from the focused project workspace, with the active main-output project workspace as fallback.

## contexts.conf

`.config/niri/contexts.conf` is the source of truth for project directories, browser profiles, outputs, terminal choice, session backend, and top-display follow behavior.

Expected context directory map:

```bash
declare -A CTX_DIR=(
  [UP]="$HOME/Developer/Work/UP/mono"
  [Webroot]="$HOME/Developer/Work/Webroot"
  [Sealant]="$HOME/Developer/OSS/Sealant"
  [Side]="$HOME"             # TODO: user hasn't placed Side yet
  [Admin]="$HOME"
)
```

Project directory map:

| Context | Directory |
| --- | --- |
| UP | `~/Developer/Work/UP/mono` |
| Webroot | `~/Developer/Work/Webroot` |
| Sealant | `~/Developer/OSS/Sealant` |
| Side | `~` TODO |
| Admin | `~` |

Browser profile map:

```bash
declare -A CTX_HELIUM_PROFILE=(
  [UP]="Profile 1"
  [Webroot]="Profile 3"
  [Sealant]="Default"
  [Side]="Default"
  [Admin]="Default"
)
```

Output and binary settings:

```bash
MAIN_OUTPUT="DP-1"
TOP_OUTPUT="DP-2"
COMMS_OUTPUT="HDMI-A-1"
HELIUM_BIN="${HELIUM_BIN:-/opt/helium-browser-bin/helium}"
CONTEXT_TERMINAL="${NIRI_CONTEXT_TERMINAL:-ghostty}"
```

Session backend:

```bash
SESSION_BACKEND="herdr"
```

`herdr` is the default for terminal cards. Set `SESSION_BACKEND="tmux"` only to force tmux directly. If Herdr is missing or exits nonzero, the dispatcher falls back to the same tmux session invisibly inside the terminal role process.

Top-display follow behavior:

```bash
TOP_FOLLOW="off"
```

`DP-2` auto-switching is DISABLED (2026-07-04): the top display changes only via
`Hyper+Escape` (ambient) or `Hyper+D` (move a window to devtools). To opt back in,
set `TOP_FOLLOW` to `devtools` or `ambient` and enable the watch service by hand
(see install.sh comments); `devtools` switches `DP-2` to the focused project's
DevTools workspace when a project browser card gains focus, `ambient` additionally
returns `DP-2` to `top-ambient` on non-browser focus.

## Browser Cards

Helium cards are tracked by cache files under:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/niri-ctx/
```

Each cache entry stores the window id plus the compositor socket it belongs to; it is valid only if that socket matches the running compositor and the window still exists as `app_id == "helium"`. A valid card that drifted to another workspace is moved back to its context workspace on the next open. Stale entries are removed automatically.

## Terminal Sessions

Terminal cards attach to Herdr sessions named from the context and role:

- `<ctx>-dev`
- `<ctx>-agents`
- `<ctx>-logs`
- `<ctx>-terminal`

These are the same names the tmux backend uses. `SESSION_BACKEND="herdr"` is the normal path for every terminal role; tmux remains the fallback when Herdr is unavailable or exits nonzero. The editor role starts `nvim` automatically on fresh Herdr dev sessions; if injection fails, the acceptable fallback is a shell in the project directory.

Herdr keys:

```text
Ctrl+S         prefix
prefix+d      detach
prefix+v      split right (herdr rejects a bare "=" binding)
prefix+-      split down
prefix+m      zoom pane
prefix+u      edit scrollback
prefix+c      new tab
prefix+1..9   switch tab
prefix+p/n    previous/next tab
prefix+h/j/k/l focus pane left/down/up/right
```

Herdr supports `herdr integration install claude` and `herdr integration install codex`, but those integrations are not installed by this repo. Opt into them later if you want agent status reporting inside Herdr.

## Comms

Run:

```sh
niri-ctx comms
```

or press `Hyper+V`.

The dispatcher opens missing Slack, Telegram, and Discord windows, ensures they are on `comms`, orders them Slack, Telegram, Discord, and stacks them into one column when possible.

## DevTools

Frontend mode was removed (2026-07-04). To put a DevTools window on the top display,
focus it and press `Hyper+D` to run:

```sh
niri-ctx devtools-here
```

## Watch Daemon (disabled)

`niri-ctx watch` exists but is NOT enabled: `TOP_FOLLOW="off"` and the
`niri-ctx-watch.service` unit is disabled and unlinked. install.sh does not
re-enable it. The unit file remains in the repo for opting back in.

## Health Check

Run:

```sh
niri-ctx doctor
```

The doctor checks niri config validation, `NIRI_SOCKET`, expected outputs, project directories, required binaries, optional Spotify support, Herdr backend/config state, the watcher service, stale legacy browser caches, and whether keybinds reference the installed `niri-ctx` path.

## Troubleshooting

If a project card opens on the wrong workspace:

- Run `niri msg pick-window` and verify the app ID matches `dev.yiannis.niri.<slug>.<role>` for terminal cards.
- Run `niri validate -c ~/.config/niri/config.kdl` and fix rule parse errors.
- Check `${XDG_CACHE_HOME:-$HOME/.cache}/niri-ctx/log` for dispatcher actions.

If a browser card focuses the wrong window:

- Run `niri-ctx doctor`.
- Remove stale entries under `${XDG_CACHE_HOME:-$HOME/.cache}/niri-ctx/` only after confirming the window no longer exists.

`DP-2` does not follow browser focus: this is intentional (`TOP_FOLLOW="off"`,
watch service disabled). Use `Hyper+Escape` / `Hyper+D`.

If terminal sessions do not start:

- Set `SESSION_BACKEND="tmux"` to bypass Herdr temporarily.
- If using Herdr, confirm `command -v herdr` succeeds and `niri-ctx doctor` does not report a backend mismatch.
