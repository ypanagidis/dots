# Niri Developer Workflow

## Monitor roles

- `DP-1`: `MAIN_BOTTOM`, primary active work display.
- `DP-2`: `TOP`, passive display above main, used for ambient workspaces and frontend DevTools.
- `HDMI-A-1`: `VERTICAL`, rotated ultrawide comms display.

`DP-1` is focused at startup by `cfg/autostart.kdl` with `focus-monitor "DP-1"` and `focus-workspace "UP"`.

## Workspaces

Main workspaces on `DP-1`:

- `UP`
- `Webroot`
- `Sealant`
- `Side`
- `Admin`

Top workspaces on `DP-2`:

- `top-ambient`: ambient/media workspace; Spotify opens here
- `UP-devtools`
- `Webroot-devtools`
- `Sealant-devtools`
- `Side-devtools`

Comms workspace on `HDMI-A-1`:

- `comms`

## Card layout

The default layout is one full-screen card per column:

- `default-column-width { proportion 1.0; }`
- `center-focused-column "always"`
- `always-center-single-column`
- preset widths: `1.0`, `0.66`, `0.5`, `0.33`

Use `Mod+Left` / `Mod+Right` or `Mod+H` / `Mod+L` to move through cards.

## Hotkeys

- Hyper emits `CTRL+ALT+Shift+Super` on this keyboard.
- `Hyper+1`: open/focus `UP`
- `Hyper+2`: open/focus `Webroot`
- `Hyper+3`: open/focus `Sealant`
- `Hyper+4`: open/focus `Side`
- `Hyper+5`: open/focus `Admin`
- `Hyper+A`: focus/open current context Helium search/docs browser
- `Hyper+G`: focus/open current context editor terminal
- `Hyper+C`: focus/open current context normal terminal
- `Hyper+R`: focus/open current context agent terminal
- `Hyper+T`: focus/open Spotify on `top-ambient`
- `Hyper+Left`, `Hyper+Right`, `Hyper+H`, `Hyper+L`: previous/next card
- `Hyper+Up`, `Hyper+Down`, `Hyper+K`, `Hyper+J`: workspace up/down on current monitor
- `Hyper+[`, `Hyper+]`: focus monitor left/right
- `Hyper+Page_Up`, `Hyper+Page_Down`: focus monitor up/down
- `Hyper+V`: open missing comms apps and restore comms layout
- `Hyper+F`: enter frontend mode for current context
- `Hyper+Escape`: return `TOP` to `top-ambient`
- `Hyper+D`: align TOP to the current context DevTools workspace, move the focused DevTools window there, then return focus to MAIN
- `Mod+Ctrl+R`: cycle preset column widths
- `Mod+Ctrl+M`: toggle maximized column
- `Mod+M`: maximize window to edges
- `Mod+Shift+M`: fullscreen window

`Hyper+Shift+...` is not a separate binding shape here because Hyper already depresses Shift.

## Project sessions

`niri-open-context` opens each project workspace as a full-width card carousel in this order:

1. Helium search/docs browser
2. Ghostty editor terminal, attached to `<context>-dev`
3. Ghostty agent terminal, running Herdr if installed or `<context>-agents` tmux
4. Helium output/app browser
5. Ghostty logs/tests terminal, attached to `<context>-logs`

It creates or attaches one tmux dev session and one agent session per context:

The number hotkeys run `niri-open-context <context>`, so they focus existing cards and create missing cards for that context. `Hyper+C` uses `<context>-terminal`; old `<context>-shell` sessions are not used for new normal terminal cards.

- `UP-dev`, `UP-agents`, `UP-logs`, `UP-terminal`
- `Webroot-dev`, `Webroot-agents`, `Webroot-logs`, `Webroot-terminal`
- `Sealant-dev`, `Sealant-agents`, `Sealant-logs`, `Sealant-terminal`
- `Side-dev`, `Side-agents`, `Side-logs`, `Side-terminal`

The editor terminal creates `<context>-dev` if missing with `nvim` as the first command, then attaches. Agent, logs, and normal terminal cards create their tmux sessions if missing, then attach.

Context terminals use Ghostty by default. The launcher starts direct Ghostty processes with `--gtk-single-instance=false`, `--class=dev.yiannis.niri.<context>.<role>`, and `--title=<context>-<role>` so Niri can distinguish project cards. To force another terminal for context cards, set `NIRI_CONTEXT_TERMINAL`.

Herdr is not installed on this system. If a `herdr` binary appears on `PATH`, the agent card will try `herdr workspace <context>`; otherwise it creates or attaches the `<context>-agents` tmux session.

Project directories default to `$HOME`. Override them with:

- `NIRI_UP_DIR`
- `NIRI_WEBROOT_DIR`
- `NIRI_SEALANT_DIR`
- `NIRI_SIDE_DIR`

## Browser profiles

Helium is the browser. The launcher uses `/opt/helium-browser-bin/helium` with Chromium profile directories discovered from `~/.config/net.imput.helium/Local State`:

- `UP`: `--profile-directory="Profile 1"`
- `Webroot`: `--profile-directory="Profile 3"`
- `Admin`: `--profile-directory="Default"`
- `Sealant`: uses the `Admin`/`Default` profile
- `Side`: uses the `Admin`/`Default` profile

The launcher stores the last observed Helium window IDs per context and browser role:

- `~/.cache/niri-browser-<context>-docs-window-id`
- `~/.cache/niri-browser-<context>-output-window-id`

Repeated context opens refocus those existing browser cards where possible. `Hyper+A` targets the search/docs browser card.

## Comms

Verified comms app IDs from `niri msg --json windows`:

- Slack: `slack`
- Discord: `discord`
- Telegram: `org.telegram.desktop`

Use `Mod+Shift+C` or run:

```sh
niri-layout-comms
```

The script opens Slack, Telegram, and Discord if missing, moves them to `comms` on `HDMI-A-1`, then tries to stack them in one column.

## Frontend mode

Run:

```sh
niri-frontend-mode UP
```

or use `Mod+F` from a project workspace.

Frontend mode:

1. Focuses `DP-1`.
2. Focuses the context workspace.
3. Opens/focuses the context Helium output/app browser.
4. Focuses `DP-2`.
5. Focuses `<context>-devtools`.
6. Moves detectable detached Helium DevTools windows for that context to the top workspace.
7. Returns keyboard focus to `DP-1`.

If DevTools matching is unreliable, focus the DevTools window manually and press `Hyper+D`. This switches `DP-1` to the project workspace, switches `DP-2` to the matching `<context>-devtools` workspace, moves the focused DevTools window to TOP, then returns keyboard focus to `DP-1`.

Use `Mod+Shift+F` or run `niri-top-ambient` to return `TOP` to `top-ambient`.

## Optional smart scrolling

`niri-smart-column-left` and `niri-smart-column-right` exist but are not bound by default. They switch cards and, when the newly focused card is Helium on a project workspace, switch `TOP` to the matching DevTools workspace.

Set `NIRI_SMART_TOP=ambient` before running them if non-browser cards should also return `TOP` to `top-ambient`; the default is to leave `TOP` unchanged.
