# MIGRATION_AUDIT.md

## 1. Command Inventory

Source state: audited working tree as-is on branch `niri`; several target files are modified locally.

### Global Dispatcher Behavior

- `bin/niri-ctx` runs with `set -euo pipefail` and sources config from repo-local `.config/niri/contexts.conf` first, then `$HOME/.config/niri/contexts.conf`; missing config exits `1` (`bin/niri-ctx:1-25`).
- Logs every invocation to `${XDG_CACHE_HOME:-$HOME/.cache}/niri-ctx/log`, rotating at 2400 lines down to 2000 (`bin/niri-ctx:8-11`, `bin/niri-ctx:44-52`, `bin/niri-ctx:1505`).
- Most mutating user commands take a global nonblocking flock on `${XDG_RUNTIME_DIR:-$LOG_DIR}/niri-ctx.lock`; if busy, they run focus-only recovery and exit `0` instead of spawning/moving windows (`bin/niri-ctx:11`, `bin/niri-ctx:1153-1203`).
- `niri_action` logs then runs `niri msg action "$@" >/dev/null` (`bin/niri-ctx:60-63`).

### `niri-ctx open <ctx> [role]`

Declared usage: `niri-ctx open <UP|Webroot|Sealant|Side|Admin|current> [all|docs|output|editor|agents|logs|term|repo:<label>]` (`bin/niri-ctx:30-31`, `bin/niri-ctx:1512-1515`).

Context aliases:
- `up`, `job1` -> `UP`
- `webroot`, `job2` -> `Webroot`
- `sealant`, `side1` -> `Sealant`
- `side`, `side2` -> `Side`
- `admin` -> `Admin`
(`bin/niri-ctx:76-87`)

Role aliases:
- default: `all`
- `browser`, `browser-docs`, `docs` -> `docs`
- `browser-output`, `output` -> `output`
- `editor`, `agents`, `logs`
- `shell`, `terminal`, `term` -> `term`
- `repo:<label>` where lowercased label matches `^[a-z0-9_-]+$`
(`bin/niri-ctx:109-126`)

`current` inference:
1. Query `niri msg --json workspaces`.
2. Try focused workspace name after stripping `-devtools`.
3. Fallback to active workspace on `$MAIN_OUTPUT`.
4. Error if neither maps to a known context.
(`bin/niri-ctx:200-216`, `bin/niri-ctx:1488-1501`)

`all` behavior:
1. Guard-focus context workspace on `$MAIN_OUTPUT`.
2. For `Admin`, use terminal role `term`; all others use `editor`.
3. Open/focus docs browser.
4. Open/focus one work terminal card.
5. Flatten tracked docs/work cards if stacked together.
6. Move docs to column index `1`, work terminal to column index `2`.
7. Refocus context workspace on `$MAIN_OUTPUT`.
8. End focus on docs browser when present.
(`bin/niri-ctx:538-554`)

Important current behavior: despite stale docs listing five cards, current `open all` creates two cards only: docs browser plus one `<ctx>.work` terminal whose roles live inside Herdr/tmux (`bin/niri-ctx:173-180`, `bin/niri-ctx:538-549`; stale docs at `.config/niri/WORKFLOW.md:79-89`).

Role behavior:
- `docs` / `output`: focus or launch Helium browser card, using cache identity and profile, then focus it (`bin/niri-ctx:441-477`, `bin/niri-ctx:556-562`).
- `editor` / `agents` / `logs` / `term` / `repo:<label>`: focus or launch the single work terminal card, then deep-link Herdr/tmux to the requested role/repo when the card already exists (`bin/niri-ctx:392-439`, `bin/niri-ctx:556-562`, `bin/niri-ctx:763-781`).

### `niri-ctx scratch`

No args (`bin/niri-ctx:1516-1521`).

Behavior:
1. Acquire global lock.
2. Guard-focus `scratch` on `$MAIN_OUTPUT`.
3. Open/focus scratch docs browser using the same Helium cache machinery with pseudo-context slug `scratch`.
4. Find or launch plain terminal with app-id `dev.yiannis.niri.scratch.term`; no Herdr/tmux attach.
5. Re-home existing scratch terminal if it drifted.
6. Flatten docs/terminal if stacked, place docs column `1`, terminal column `2`.
7. Refocus scratch workspace and end focus on terminal.
(`bin/niri-ctx:96-98`, `bin/niri-ctx:1057-1095`)

### `niri-ctx comms`

No args (`bin/niri-ctx:1522-1527`).

Behavior:
1. Acquire global lock.
2. For Slack, Telegram, Discord, find oldest window by app-id or launch if installed.
3. Wait up to 10 seconds for launched apps.
4. Move found windows to `comms` with `--focus false`.
5. Guard-focus `comms` on `$COMMS_OUTPUT`.
6. Ignore floating windows for stacking.
7. If tiled comms windows are not already one shared column:
   - flatten all multi-window tiled columns on the workspace;
   - move comms columns to indices Slack=`1`, Telegram=`2`, Discord=`3` for present apps;
   - focus Slack, set column width `100%`;
   - repeatedly consume the immediate right column into Slack’s column, with four 100ms retries per app.
8. Set each stacked window height to `100 / count` percent.
9. End focus on first stacked app.
(`bin/niri-ctx:904-937`, `bin/niri-ctx:939-1055`)

### `niri-ctx devtools-here`

No args (`bin/niri-ctx:1528-1533`).

Behavior:
1. Acquire global lock.
2. Query focused window from `niri msg --json windows`.
3. Resolve its workspace id and workspace name.
4. Map workspace name to context, stripping `-devtools`.
5. No-op for unknown contexts and for `Admin`.
6. Move focused window to `${ctx}-devtools` with `--focus false`.
7. Guard-focus `${ctx}-devtools` on `$TOP_OUTPUT`.
8. Guard-focus original context on `$MAIN_OUTPUT`.
(`bin/niri-ctx:1097-1116`)

Dropped legacy behavior: old script also used `move-window-to-monitor --id "$id" "$TOP_OUTPUT"` (`legacy/niri-scripts/niri-move-focused-devtools:44-52`); current script deliberately relies on named workspace placement only.

### `niri-ctx top-ambient`

No args (`bin/niri-ctx:1534-1538`).

Behavior:
1. Guard-focus `top-ambient` on `$TOP_OUTPUT`.
2. Return focus to `$MAIN_OUTPUT` monitor only.
(`bin/niri-ctx:1148-1151`)

### `niri-ctx spotify`

No args (`bin/niri-ctx:1539-1544`).

Behavior:
1. Acquire global lock.
2. Find oldest `app_id == "Spotify"`.
3. If absent, launch `spotify-launcher`, else `spotify`, then wait up to 20 seconds for app-id `Spotify`.
4. Move window to named workspace `top-ambient` with `--focus false`.
5. Guard-focus `top-ambient` on `$TOP_OUTPUT`.
6. Focus Spotify window.
(`bin/niri-ctx:1118-1146`)

Important workaround: current script does not call `move-window-to-monitor` after moving to named workspace, because that can re-home the window to whatever workspace is active on the output (`bin/niri-ctx:1140-1143`).

### `niri-ctx watch`

No args (`bin/niri-ctx:1545-1549`).

Behavior:
1. Exit quietly if `NIRI_SOCKET` unset or `niri msg --json workspaces` unreachable.
2. Subscribe to `niri msg --json event-stream`.
3. Maintain Bash associative caches:
   - `WIN_APP[id]`
   - `WIN_WS[id]`
   - `WS_NAME[id]`
   - `WS_OUTPUT[id]`
4. On `WorkspacesChanged`, rebuild workspace name/output cache.
5. On `WindowsChanged`, rebuild window app/workspace cache.
6. On `WindowOpenedOrChanged`, update one window and also evaluate focus if event says `is_focused == true`.
7. On `WindowClosed`, remove window cache entry.
8. On `WindowFocusChanged`, evaluate top-follow.
9. If event stream ends, reconnect with exponential backoff from 1s to 30s.
(`bin/niri-ctx:1210-1329`)

Top-follow logic:
- Disabled when `TOP_FOLLOW=off`.
- Defaults to `devtools` if variable absent.
- Ignores events during global lock or until `WATCH_IGNORE_UNTIL`.
- Only reacts to focused windows on `$MAIN_OUTPUT`.
- Ignores `Admin`.
- `TOP_FOLLOW=devtools`: focused Helium on project workspace switches `$TOP_OUTPUT` to `${ctx}-devtools`.
- `TOP_FOLLOW=ambient`: focused non-Helium on project workspace switches `$TOP_OUTPUT` to `top-ambient`.
(`bin/niri-ctx:1225-1260`; disabled config `.config/niri/contexts.conf:20`)

### `niri-ctx startup`

No args (`bin/niri-ctx:1550-1554`).

Behavior:
1. For up to 75 attempts, every 0.2s, query workspaces.
2. Wait until workspace `UP` exists on `$MAIN_OUTPUT`.
3. Guard-focus `UP` on `$MAIN_OUTPUT`.
4. Log timeout if not found.
(`bin/niri-ctx:1331-1345`)

The docs state this avoids workspace auto-back-and-forth (`.config/niri/WORKFLOW.md:17-24`).

### `niri-ctx doctor`

No args (`bin/niri-ctx:1555-1559`).

Checks:
- `niri` binary exists and `niri validate -c "$REPO_ROOT/.config/niri/config.kdl"` passes.
- `NIRI_SOCKET` is set and `niri msg --json workspaces` succeeds.
- `$MAIN_OUTPUT` present = fail if missing; `$TOP_OUTPUT` and `$COMMS_OUTPUT` warn if missing.
- `CTX_REPOS` entries exist, are `label=dir`, and directories exist.
- `jq`, `tmux`, and `$CONTEXT_TERMINAL` binaries exist.
- Helium exists via `$HELIUM_BIN` executable or `command -v helium`.
- Spotify launcher presence is informational.
- Herdr availability matches `SESSION_BACKEND`.
- `~/.config/herdr/config.toml` symlink points to repo config.
- Herdr session names are listed if possible.
- `systemctl --user is-active niri-ctx-watch`.
- Warns on legacy cache files `~/.cache/niri-browser-*`.
- Verifies `$HOME/.local/bin/niri-ctx` exists and keybinds mention `niri-ctx`.
(`bin/niri-ctx:1347-1486`)

### `niri-ctx --tmux-role <ctx> <role>`

Internal terminal entrypoint, invoked by Ghostty/Alacritty spawns (`bin/niri-ctx:369-389`, `bin/niri-ctx:1507-1511`).

Accepted roles: `editor`, `agents`, `logs`, `term`, `repo:<label>` after normalization (`bin/niri-ctx:878-888`).

Behavior:
1. Normalize context and role.
2. Unset `TMUX` and `TMUX_PANE`.
3. `cd` to default repo dir, fallback `$HOME`.
4. Set terminal title OSC to `<ctx>-work`.
5. Resolve session name `<ctx>-work`.
6. If `SESSION_BACKEND=herdr` and `herdr` exists, try Herdr attach.
7. If Herdr unavailable or fails quickly, attach tmux fallback.
(`bin/niri-ctx:878-902`)

## 2. Configuration Surface

### Variables read from `.config/niri/contexts.conf`

- `CTX_REPOS`: Bash associative array. Format: `CTX_REPOS[Context]="label=dir label2=dir2"`, separated by spaces; paths must not contain spaces. Each label is a Herdr workspace / tmux window prefix; first entry is default repo. Admin special-cases to one plain workspace (`.config/niri/contexts.conf:1-12`, `bin/niri-ctx:135-170`, `bin/niri-ctx:640-647`).
- `CTX_HELIUM_PROFILE`: Bash associative array mapping context to Helium `--profile-directory`; default lookup is `Default` if missing (`.config/niri/contexts.conf:13-15`, `bin/niri-ctx:462`).
- `MAIN_OUTPUT`: main project carousel output. Required in practice; used by focus/open/startup/watch/doctor (`.config/niri/contexts.conf:16`, `bin/niri-ctx:208`, `bin/niri-ctx:540`, `bin/niri-ctx:1251`, `bin/niri-ctx:1336-1339`).
- `TOP_OUTPUT`: top ambient/devtools output (`.config/niri/contexts.conf:16`, `bin/niri-ctx:1114`, `bin/niri-ctx:1144`, `bin/niri-ctx:1236`).
- `COMMS_OUTPUT`: vertical comms output (`.config/niri/contexts.conf:16`, `bin/niri-ctx:1004`, `bin/niri-ctx:1178`).
- `HELIUM_BIN`: executable path. Config default is `${HELIUM_BIN:-/opt/helium-browser-bin/helium}`; script falls back to `command -v helium` (`.config/niri/contexts.conf:17`, `bin/niri-ctx:268-279`).
- `CONTEXT_TERMINAL`: `ghostty` or `alacritty`. Config default is `${NIRI_CONTEXT_TERMINAL:-ghostty}`. Other values are rejected because app-id detection depends on terminal class support (`.config/niri/contexts.conf:18`, `bin/niri-ctx:373-388`, `bin/niri-ctx:1066-1077`).
- `SESSION_BACKEND`: `herdr` or `tmux`. Config default is `${SESSION_BACKEND:-herdr}`; script post-source fallback is `${SESSION_BACKEND:-${AGENTS_BACKEND:-herdr}}` (`.config/niri/contexts.conf:19`, `bin/niri-ctx:26`, `bin/niri-ctx:894-901`).
- `TOP_FOLLOW`: `devtools`, `ambient`, or `off`. Current config sets `off`; watcher default if unset is effectively `devtools` (`.config/niri/contexts.conf:20`, `bin/niri-ctx:1245`, `bin/niri-ctx:1254-1257`).

### Environment variables read

- `HOME`: config paths, repo directories, Herdr socket paths, install target assumptions (`bin/niri-ctx:8`, `bin/niri-ctx:19`, `bin/niri-ctx:623`, `.config/niri/contexts.conf:7-11`).
- `XDG_CACHE_HOME`: log/cache root fallback (`bin/niri-ctx:8`).
- `XDG_RUNTIME_DIR`: lock-file root fallback (`bin/niri-ctx:11`).
- `NIRI_SOCKET`: browser cache socket validation, watcher/doctor reachability (`bin/niri-ctx:339-341`, `bin/niri-ctx:359`, `bin/niri-ctx:1264-1270`, `bin/niri-ctx:1366-1370`).
- `HELIUM_BIN`: overrides default Helium path in config (`.config/niri/contexts.conf:17`).
- `NIRI_CONTEXT_TERMINAL`: overrides terminal choice in config (`.config/niri/contexts.conf:18`).
- `SESSION_BACKEND`: external override before/inside config (`.config/niri/contexts.conf:19`, `bin/niri-ctx:26`).
- `AGENTS_BACKEND`: fallback only if `SESSION_BACKEND` unset after source (`bin/niri-ctx:26`).
- `PWD`: used as `HERDR_STARTUP_CWD` for attach (`bin/niri-ctx:861`).
- `HERDR_ENV`, `HERDR_PANE_ID`, `HERDR_SESSION`, `HERDR_SOCKET_PATH`, `HERDR_TAB_ID`, `HERDR_WORKSPACE_ID`: explicitly stripped before nested Herdr attach (`bin/niri-ctx:857-861`).
- `TMUX`, `TMUX_PANE`: explicitly unset before tmux/herdr role process (`bin/niri-ctx:889`).
- `PATH`: implied by all `command -v` checks and process spawns.

Test-only env:
- `NIRI_CTX`: overrides tested dispatcher path in convergence harness (`tests/converge.sh:7`).

## 3. Contexts and Workspaces

### Contexts and repos

From `.config/niri/contexts.conf:6-12`:

| Context | Slug | Repos / dirs | Default repo | Helium profile | Session |
| --- | --- | --- | --- | --- | --- |
| `UP` | `up` | `mono=$HOME/Developer/Work/UP/mono` | `mono` | `Profile 1` | `UP-work` |
| `Webroot` | `webroot` | `webroot=$HOME/Developer/Work/Webroot` | `webroot` | `Profile 3` | `Webroot-work` |
| `Sealant` | `sealant` | `core=$HOME/Developer/OSS/Sealant/Core`, `sealantd=$HOME/Developer/OSS/Sealant/Sealantd` | `core` | `Default` | `Sealant-work` |
| `Side` | `side` | `sandbox=$HOME/Developer/sandbox` | `sandbox` | `Default` | `Side-work` |
| `Admin` | `admin` | `term=$HOME` | `term` | `Default` | `Admin-work` |

Admin special cases:
- Full open uses `term` role instead of `editor` (`bin/niri-ctx:539-546`).
- Herdr layout convergence no-ops for Admin (`bin/niri-ctx:650-651`).
- Herdr focus only focuses workspace labelled `term` (`bin/niri-ctx:711-714`).
- No devtools workspace; `devtools-here` returns (`bin/niri-ctx:1109-1111`).
- No `Admin-devtools` workspace is declared (`.config/niri/cfg/workspaces.kdl:29-47`).

Pseudo-context:
- `scratch` is valid only for app-id/cache slug, not an `open` target (`bin/niri-ctx:89-100`).
- Workspace `scratch` lives on `DP-1` (`.config/niri/cfg/workspaces.kdl:5-7`).
- Scratch terminal app-id is `dev.yiannis.niri.scratch.term` (`bin/niri-ctx:1060-1064`).

### Workspaces and output placement

Declaration order defines workspace order (`.config/niri/cfg/workspaces.kdl:1-4`):

- `DP-1`: `scratch`, `Webroot`, `UP`, `Sealant`, `Side`, `Admin` (`.config/niri/cfg/workspaces.kdl:5-27`).
- `DP-2`: `top-ambient`, `UP-devtools`, `Webroot-devtools`, `Sealant-devtools`, `Side-devtools` (`.config/niri/cfg/workspaces.kdl:29-47`).
- `HDMI-A-1`: `comms` (`.config/niri/cfg/workspaces.kdl:49-51`).

Keybind direct workspace movement depends on these names for `scratch`, `Webroot`, `UP`, `Sealant`, `Side`, `Admin` (`.config/niri/cfg/keybinds.kdl:98-103`).

## 4. Monitor Model

Actual output names and roles:
- `DP-1`: main work display / project carousel. Configured `5120x2880@180.003`, scale `2`, normal transform, position `x=0 y=1080` (`.config/niri/cfg/display.kdl:5-10`; role docs `.config/niri/WORKFLOW.md:11-15`).
- `DP-2`: top display for `top-ambient` and project devtools. Configured `1920x1080@60.000`, scale `1`, transform `180`, position `x=320 y=0` (`.config/niri/cfg/display.kdl:12-17`).
- `HDMI-A-1`: comms display. Configured `3440x1440@59.973`, scale `1.5`, transform `270`, position `x=2560 y=227` (`.config/niri/cfg/display.kdl:19-24`).

Output names are assumed in:
- `.config/niri/contexts.conf:16`
- `.config/niri/cfg/display.kdl:5-24`
- `.config/niri/cfg/workspaces.kdl:5-51`
- `.config/niri/cfg/rules.kdl:10-32`
- `bin/niri-ctx` through `$MAIN_OUTPUT`, `$TOP_OUTPUT`, `$COMMS_OUTPUT` in focus/open/watch/startup/doctor paths (`bin/niri-ctx:200-247`, `bin/niri-ctx:980-1007`, `bin/niri-ctx:1097-1151`, `bin/niri-ctx:1225-1260`, `bin/niri-ctx:1331-1345`, `bin/niri-ctx:1373-1381`)
- legacy scripts hardcode `DP-1`, `DP-2`, `HDMI-A-1` (`legacy/niri-scripts/niri-frontend-mode:4-5`, `legacy/niri-scripts/niri-layout-comms:4-5`, `legacy/niri-scripts/niri-top-ambient:4-6`)

## 5. Window Identity Model

### Terminal cards

- Prefix: `dev.yiannis.niri` (`bin/niri-ctx:4`).
- Current work terminal app-id: `dev.yiannis.niri.<slug>.work` (`bin/niri-ctx:173-177`).
- Current terminal title: `<Context>-work` (`bin/niri-ctx:179-180`).
- Scratch terminal app-id: `dev.yiannis.niri.scratch.term`; title `scratch` (`bin/niri-ctx:1060-1074`).
- Ghostty launch: `ghostty --gtk-single-instance=false --class="$app_id" --title="$title" -e "$SCRIPT_PATH" --tmux-role "$ctx" "$role"` (`bin/niri-ctx:373-379`).
- Alacritty launch: `alacritty --class "$app_id,$app_id" --title "$title" -e "$SCRIPT_PATH" --tmux-role "$ctx" "$role"` (`bin/niri-ctx:380-385`).

Rules place both current `work` and legacy per-role ids:
- `dev.yiannis.niri.up.(work|editor|agents|logs|term)` -> `UP`
- `dev.yiannis.niri.webroot.(work|editor|agents|logs|term)` -> `Webroot`
- `dev.yiannis.niri.sealant.(work|editor|agents|logs|term)` -> `Sealant`
- `dev.yiannis.niri.side.(work|editor|agents|logs|term)` -> `Side`
- `dev.yiannis.niri.admin.(work|editor|agents|logs|term)` -> `Admin`
(`.config/niri/cfg/rules.kdl:35-65`)

### Browser cards

- App-id matched: exactly `helium` (`bin/niri-ctx:319-323`, `bin/niri-ctx:345-346`, `bin/niri-ctx:463`).
- No Niri window rule places Helium; dispatcher moves browser windows to context workspace after finding/launching (`bin/niri-ctx:441-477`).
- Browser cache path: `${XDG_CACHE_HOME:-$HOME/.cache}/niri-ctx/browser-<slug>-<role>.id` (`bin/niri-ctx:263-266`).
- Cache format: line 1 window id, line 2 `NIRI_SOCKET`; cache invalidates on non-uint id, socket mismatch, missing window, or non-Helium app-id (`bin/niri-ctx:327-353`).
- New browser launch uses configured profile and `--new-window about:blank` (`bin/niri-ctx:459-466`).
- Matching a new Helium window excludes the pre-launch id set (`bin/niri-ctx:313-325`, `bin/niri-ctx:463-466`).
- Roles are only `docs` and `output`; output browser is on-demand and not part of full open (`bin/niri-ctx:441-446`, `bin/niri-ctx:543-545`).

### Comms / Spotify

- Slack app-id: `slack` (`bin/niri-ctx:904-907`; rule `.config/niri/cfg/rules.kdl:9-13`).
- Telegram app-id: `org.telegram.desktop` (`bin/niri-ctx:904-908`; rule `.config/niri/cfg/rules.kdl:21-25`).
- Discord app-id: `discord` (`bin/niri-ctx:904-909`; rule `.config/niri/cfg/rules.kdl:15-19`).
- Spotify app-id: `Spotify` (`bin/niri-ctx:1118-1119`; rule `.config/niri/cfg/rules.kdl:27-33`).

### Other declarative rules

- Global window radius 20 and clip-to-geometry (`.config/niri/cfg/rules.kdl:1-4`).
- Steam main windows float except title `Steam`; notification toast placement bottom-right (`.config/niri/cfg/rules.kdl:67-78`).
- Layer rule namespace regex `^noctalia-wallpaper*` places wallpaper in backdrop (`.config/niri/cfg/rules.kdl:80-83`).

## 6. Session Backend

### Herdr model

Current session naming:
- All terminal roles for a context use one session: `<Context>-work` (`bin/niri-ctx:614-619`).
- Valid Herdr session names include current `-work` plus legacy `-dev`, `-agents`, `-logs`, `-terminal` for cleanup/addressability (`bin/niri-ctx:608-612`).
- Socket path: `$HOME/.config/herdr/sessions/<session>/herdr.sock` (`bin/niri-ctx:622-624`).

Repo-major canonical layout:
- One Herdr workspace per `CTX_REPOS` entry.
- Each non-Admin repo workspace has tabs `editor`, `agents`, `logs` in that order.
- Editor tabs created by dispatcher run `nvim`.
- Admin bypasses repo/tab convergence.
(`bin/niri-ctx:640-697`)

Fresh Herdr bootstrap:
1. Before attach, arm background bootstrap only if session did not already exist (`bin/niri-ctx:846-850`).
2. Wait up to 10s for socket, then sleep 0.5s (`bin/niri-ctx:817-824`).
3. Rename workspace `w1` to default repo label (`bin/niri-ctx:825`).
4. Admin exits after rename (`bin/niri-ctx:826`).
5. Read first tab id from `tab list --workspace w1`, rename to `editor` (`bin/niri-ctx:827-831`).
6. Read first pane id from `pane list --workspace w1`, run `nvim` (`bin/niri-ctx:832-834`).
7. Ensure full layout, then focus requested role (`bin/niri-ctx:835-836`).

Herdr CLI calls:
- `herdr session list --json` (`bin/niri-ctx:798-805`, `bin/niri-ctx:1449-1455`)
- `herdr session stop <session>` and `herdr session delete <session>` for fresh orphan reaping (`bin/niri-ctx:789-796`)
- `HERDR_SOCKET_PATH=<sock> herdr workspace list` (`bin/niri-ctx:652`, `bin/niri-ctx:709`)
- `workspace rename <id> <label>` (`bin/niri-ctx:664`, `bin/niri-ctx:825`)
- `workspace create --label <label> --cwd <dir> --no-focus` (`bin/niri-ctx:669`)
- `workspace create --label <label> --cwd <dir> --focus` (`bin/niri-ctx:730`)
- `workspace focus <wsid>` (`bin/niri-ctx:713`, `bin/niri-ctx:733`)
- `tab list --workspace <wsid>` (`bin/niri-ctx:676`, `bin/niri-ctx:745`, `bin/niri-ctx:829`)
- `tab rename <tabid> editor` (`bin/niri-ctx:673`, `bin/niri-ctx:687`, `bin/niri-ctx:831`)
- `tab create --workspace <wsid> --label <role> --cwd <dir> --no-focus` (`bin/niri-ctx:691`)
- `tab create --workspace <wsid> --label <role> --focus` with no `--cwd`, relying on Herdr `new_cwd=follow` (`bin/niri-ctx:750-752`)
- `tab focus <tabid>` (`bin/niri-ctx:758`)
- `pane run <pane> nvim` (`bin/niri-ctx:634-638`)
- `pane list --workspace w1` (`bin/niri-ctx:832-833`)
- `env -u HERDR_* HERDR_STARTUP_CWD="$PWD" herdr --session "$session"` (`bin/niri-ctx:857-862`)

Herdr 0.7.1 assumptions:
- Socket CLI replies are JSON; comment specifically verified `tab list -> {"result":{"tabs":[{"tab_id":"w1:t1",...}]}}` (`bin/niri-ctx:827-828`).
- Config notes Herdr 0.7.1 rejects `prefix+equal`, so split bindings are `prefix+v` and `prefix+minus` (`.config/herdr/config.toml:104-107`).

Herdr config surface:
- `onboarding=false` (`.config/herdr/config.toml:4-6`)
- theme `terminal`, `auto_switch=false` (`.config/herdr/config.toml:8-29`)
- prefix `ctrl+s`, detach `prefix+d`, workspace prev/next `prefix+ctrl+k/j`, switch tabs `prefix+1..9`, scrollback `prefix+u`, split vertical `prefix+v`, split horizontal `prefix+minus`, zoom `prefix+m`, mouse capture true (`.config/herdr/config.toml:54-109`, `.config/herdr/config.toml:140-157`).

### Migration/adoption logic

- If default repo workspace missing but legacy workspace `editor` exists, rename `editor` workspace to default repo label; running nvim survives (`bin/niri-ctx:640-646`, `bin/niri-ctx:661-666`).
- If editor tab missing and default tab labelled `1` at number `1` exists, rename it to `editor` to preserve tab order (`bin/niri-ctx:678-689`).
- Legacy `agents` / `logs` workspaces are intentionally left for user cleanup (`bin/niri-ctx:643-646`).
- Role deep-links act on currently focused repo workspace unless focused workspace is a legacy role label; then they fallback to default repo (`bin/niri-ctx:699-758`).
- `repo:<label>` focuses or creates a repo workspace for that label (`bin/niri-ctx:724-734`).

### Tmux fallback

- Same session name `<Context>-work` (`bin/niri-ctx:614-619`, `bin/niri-ctx:878-902`).
- Admin creates/uses one tmux session in `$HOME`, window `term` (`bin/niri-ctx:570-573`, `bin/niri-ctx:592-605`).
- Non-Admin creates tmux windows per repo/role:
  - first repo `label/editor` starts `nvim` in `tmux new-session`
  - other repo editor windows run `nvim`
  - `label/agents` shell
  - `label/logs` shell
(`bin/niri-ctx:566-590`)
- `repo:<label>` selects `<label>/editor`; role selects `<current_repo>/<role>` based on active tmux window name, fallback default repo (`bin/niri-ctx:592-605`, `bin/niri-ctx:768-780`).
- Attach via `exec tmux attach-session -t "$session"` (`bin/niri-ctx:605`).

## 7. Niri IPC Surface

### Queries

Current dispatcher uses only:
- `niri msg --json workspaces` (`bin/niri-ctx:202`, `220`, `231`, `399`, `449`, `497`, `519`, `1006`, `1082`, `1104`, `1207`, `1268`, `1334`, `1366`)
- `niri msg --json windows` (`bin/niri-ctx:253`, `345`, `463`, `482`, `490`, `523`, `944`, `952`, `966`, `1099`)
- `niri msg --json event-stream` (`bin/niri-ctx:283`, `1324`)
- `niri validate -c "$REPO_ROOT/.config/niri/config.kdl"` in doctor/install (`bin/niri-ctx:1355-1361`, `install.sh:84-89`)

Legacy-only, not current dispatcher:
- `niri msg --json focused-window` (`legacy/niri-scripts/niri-move-focused-devtools:32`, `legacy/niri-scripts/niri-smart-column-left:7`)
- `niri msg outputs` only documented for manual verification (`.config/niri/cfg/workspaces.kdl:2`, `.config/niri/cfg/display.kdl:2`)

### Actions

Through `niri_action` current dispatcher invokes:
- `focus-monitor <output>` (`bin/niri-ctx:218-227`, `bin/niri-ctx:229-247`, `bin/niri-ctx:1148-1151`)
- `focus-workspace <name>` (`bin/niri-ctx:229-247`)
- `focus-window --id <id>` (`bin/niri-ctx:363-367`, plus callers)
- `move-window-to-workspace --window-id <id> --focus false <workspace>` (`bin/niri-ctx:402`, `452`, `472`, `1001`, `1085`, `1113`, `1143`)
- `move-column-to-index <index>` (`bin/niri-ctx:494-507`, `bin/niri-ctx:1028-1031`)
- `expel-window-from-column` (`bin/niri-ctx:512-536`, `bin/niri-ctx:962-978`)
- `set-column-width "100%"` (`bin/niri-ctx:1032-1034`)
- `consume-window-into-column` (`bin/niri-ctx:1037-1044`)
- `set-window-height --id <id> "<pct>%"` (`bin/niri-ctx:1050-1053`)

Tests additionally use:
- `move-window-to-workspace --window-id ... --focus false ...` (`tests/converge.sh:90-91`, `tests/converge.sh:123`, `tests/converge.sh:137`)
- `focus-window --id ...` and `consume-window-into-column` (`tests/converge.sh:100-101`)

### jq expressions used against Niri JSON

Workspaces:
- Case-insensitive workspace id by name: `first(.[] | select((.name // "" | ascii_downcase) == ($workspace | ascii_downcase)) | .id) // empty` (`bin/niri-ctx:183-188`).
- Focused workspace name: `first(.[] | select(.is_focused) | .name // empty) // empty` (`bin/niri-ctx:190-192`).
- Active workspace on output: `first(.[] | select(.output == $output and .is_active) | .name // empty) // empty` (`bin/niri-ctx:194-198`).
- Output exists: `any(.[]; .output == $output)` (`bin/niri-ctx:221`).
- Output focused: `any(.[]; .output == $output and .is_focused)` (`bin/niri-ctx:223`, `bin/niri-ctx:240`).
- Workspace object by name: `first(.[] | select((.name // "" | ascii_downcase) == ($workspace | ascii_downcase))) // empty` (`bin/niri-ctx:232-234`).
- Fields from target workspace: `.is_focused`, `.is_active`, `.output // empty` (`bin/niri-ctx:236-239`).
- Startup has UP on main output: `any(.[]; .output == $output and .name == "UP")` (`bin/niri-ctx:1336`).
- Doctor output present: `any(.[]; .output == $output)` (`bin/niri-ctx:1374`).

Windows:
- Oldest id for app-id: `[.[] | select(.app_id == $app_id) | .id] | sort | (.[0] // empty)` (`bin/niri-ctx:249-255`).
- Cache validates Helium id: `first(.[] | select(.id == $id and .app_id == "helium") | .id) // empty` (`bin/niri-ctx:345-346`).
- Existing Helium ids before launch: `[.[] | select(.app_id == "helium") | .id | tostring] | join(",")` (`bin/niri-ctx:463`).
- Column index for id: `first(.[] | select(.id == $id) | .layout.pos_in_scrolling_layout[0]) // empty` (`bin/niri-ctx:482-484`).
- Workspace id for window id: `first(.[] | select(.id == $id) | .workspace_id) // empty` (`bin/niri-ctx:490-491`).
- Window floating with missing-window default true: `[.[] | select(.id == $id) | .is_floating] | if length == 0 then true else first end` (`bin/niri-ctx:944-945`).
- Right column first id: select same workspace, tiled, column greater than current, sort by column/row, first id (`bin/niri-ctx:952-956`).
- Flatten tracked cards: select tracked ids on workspace, tiled, group by column, pick last row id from first multi-window column (`bin/niri-ctx:523-530`).
- Flatten whole workspace: same but for all tiled windows on workspace (`bin/niri-ctx:966-972`).
- Devtools focused id: `first(.[] | select(.is_focused) | .id) // empty` (`bin/niri-ctx:1100`).
- Devtools focused workspace id: `first(.[] | select(.id == $id) | .workspace_id) // empty` (`bin/niri-ctx:1102`).
- Devtools workspace name by workspace id: `first(.[] | select(.id == $ws) | .name // empty) // empty` (`bin/niri-ctx:1105`).

Event stream:
- Wait generic filter is dynamic via `jq -r "$jq_filter"` (`bin/niri-ctx:281-310`).
- Wait app-id filter: `first((.WindowsChanged.windows[]?, .WindowOpenedOrChanged.window?) | select(.app_id == env.NIRI_CTX_WAIT_APP_ID) | .id) // empty` (`bin/niri-ctx:306-310`).
- Wait new Helium filter: `first((.WindowsChanged.windows[]?, .WindowOpenedOrChanged.window?) | select(.app_id == "helium") | (.id | tostring) as $wid | select((env.NIRI_CTX_BEFORE_IDS | split(",") | map(select(length > 0)) | index($wid)) | not) | .id) // empty` (`bin/niri-ctx:313-324`).
- Event type: `keys[0] // empty` (`bin/niri-ctx:1280`).
- Workspace cache: `.WorkspacesChanged.workspaces[] | [.id, (.name // ""), (.output // "")] | @tsv` (`bin/niri-ctx:1289`).
- Window cache: `.WindowsChanged.windows[] | [.id, (.app_id // ""), (.workspace_id // "")] | @tsv` (`bin/niri-ctx:1298`).
- Open/change fields: `.WindowOpenedOrChanged.window.id // empty`, `.app_id // ""`, `.workspace_id // ""`, `.is_focused // false` (`bin/niri-ctx:1301-1308`).
- Closed/focus ids: `.WindowClosed.id // empty`, `.WindowFocusChanged.id // empty` (`bin/niri-ctx:1314`, `bin/niri-ctx:1320`).

## 8. Keybindings

Every keybind that calls `niri-ctx`:

- `CTRL+ALT+Shift+Super+1`: `"/home/yiannis/.local/bin/niri-ctx" "scratch"` (`.config/niri/cfg/keybinds.kdl:87`)
- `CTRL+ALT+Shift+Super+2`: `"/home/yiannis/.local/bin/niri-ctx" "open" "Webroot"` (`.config/niri/cfg/keybinds.kdl:88`)
- `CTRL+ALT+Shift+Super+3`: `"/home/yiannis/.local/bin/niri-ctx" "open" "UP"` (`.config/niri/cfg/keybinds.kdl:89`)
- `CTRL+ALT+Shift+Super+4`: `"/home/yiannis/.local/bin/niri-ctx" "open" "Sealant"` (`.config/niri/cfg/keybinds.kdl:90`)
- `CTRL+ALT+Shift+Super+5`: `"/home/yiannis/.local/bin/niri-ctx" "open" "Side"` (`.config/niri/cfg/keybinds.kdl:91`)
- `CTRL+ALT+Shift+Super+6`: `"/home/yiannis/.local/bin/niri-ctx" "open" "Admin"` (`.config/niri/cfg/keybinds.kdl:92`)
- `CTRL+ALT+Shift+Super+A`: `"/home/yiannis/.local/bin/niri-ctx" "open" "current" "docs"` (`.config/niri/cfg/keybinds.kdl:113`)
- `CTRL+ALT+Shift+Super+G`: `"/home/yiannis/.local/bin/niri-ctx" "open" "current" "editor"` (`.config/niri/cfg/keybinds.kdl:114`)
- `CTRL+ALT+Shift+Super+C`: `"/home/yiannis/.local/bin/niri-ctx" "open" "current" "agents"` (`.config/niri/cfg/keybinds.kdl:115`)
- `CTRL+ALT+Shift+Super+R`: `"/home/yiannis/.local/bin/niri-ctx" "open" "current" "agents"` (`.config/niri/cfg/keybinds.kdl:116`)
- `CTRL+ALT+Shift+Super+T`: `"/home/yiannis/.local/bin/niri-ctx" "spotify"` (`.config/niri/cfg/keybinds.kdl:117`)
- `CTRL+ALT+Shift+Super+Escape`: `"/home/yiannis/.local/bin/niri-ctx" "top-ambient"` (`.config/niri/cfg/keybinds.kdl:118`)
- `CTRL+ALT+Shift+Super+V`: `"/home/yiannis/.local/bin/niri-ctx" "comms"` (`.config/niri/cfg/keybinds.kdl:119`)
- `CTRL+ALT+Shift+Super+D`: `"/home/yiannis/.local/bin/niri-ctx" "devtools-here"` (`.config/niri/cfg/keybinds.kdl:120`)

Note: `.config/niri/WORKFLOW.md` hotkey list is stale for number keys; it says Hyper+1 opens `UP`, but actual keybind Hyper+1 opens `scratch` and Hyper+3 opens `UP` (`.config/niri/WORKFLOW.md:51-55`, `.config/niri/cfg/keybinds.kdl:87-92`).

## 9. Systemd / Autostart

Niri autostart:
- Starts Noctalia shell: `spawn-sh-at-startup "qs -c noctalia-shell"` (`.config/niri/cfg/autostart.kdl:4`).
- Starts dispatcher sync: `spawn-sh-at-startup "/home/yiannis/.local/bin/niri-ctx startup"` (`.config/niri/cfg/autostart.kdl:5`).

Watcher unit:
- Unit file: `.config/systemd/user/niri-ctx-watch.service`.
- `ExecStart=%h/.local/bin/niri-ctx watch`.
- `Restart=on-failure`, `RestartSec=2`.
- Wanted by `graphical-session.target`.
(`.config/systemd/user/niri-ctx-watch.service:1-13`)

Current state by repo policy:
- Watch daemon disabled by default; install does not link/enable it (`install.sh:62-68`).
- Docs explicitly say `TOP_FOLLOW="off"` and unit is disabled/unlinked (`.config/niri/WORKFLOW.md:259-263`).
- `install.sh` only reports if already enabled and leaves it alone (`install.sh:66-68`).
- `doctor` reports active state via `systemctl --user is-active niri-ctx-watch` (`bin/niri-ctx:1457-1459`).

Install behavior:
- Symlinks `bin/niri-ctx` to `$HOME/.local/bin/niri-ctx` (`install.sh:22-25`).
- Symlinks Herdr config to `$HOME/.config/herdr/config.toml`, backing up real file first (`install.sh:27-34`).
- Reloads Herdr config if Herdr process running (`install.sh:35-37`).
- Removes legacy scripts from `$HOME/.local/bin` only if identical to repo legacy copies (`install.sh:39-60`).
- Runs `niri validate` and `niri-ctx doctor` (`install.sh:84-98`).

## 10. Known Hacks / Workarounds

- Guarded focus to avoid workspace-auto-back-and-forth: `ctx_focus_workspace` checks target focused/active/output before `focus-workspace` (`bin/niri-ctx:229-247`; docs `.config/niri/WORKFLOW.md:23`).
- Never call `move-window-to-monitor` after moving to a named workspace in current Spotify/devtools paths; legacy did this and current comment explains it can move to whatever workspace is active on the output (`bin/niri-ctx:1140-1143`, `legacy/niri-scripts/niri-open-spotify:22-26`, `legacy/niri-scripts/niri-move-focused-devtools:49-50`).
- Ghostty/terminal never-maps self-heal: if terminal app-id window does not appear in 10s, kill matching terminal command line with `pkill -f -- "-class[= ]..."` and retry once; final failure also reaps hung instance (`bin/niri-ctx:415-438`).
- Fresh Herdr orphan reaping: if a launch created a Herdr session but no terminal window mapped, stop/delete only that fresh session (`bin/niri-ctx:412-435`, `bin/niri-ctx:784-796`).
- Herdr nested attach workaround: strip inherited Herdr env markers before `herdr --session` (`bin/niri-ctx:857-862`).
- Herdr first-frame/bootstrap race workaround: background bootstrap waits for socket, sleeps 0.5s, adopts `w1`, renames first tab, starts nvim, then converges layout (`bin/niri-ctx:807-838`).
- Herdr 0.7.1 socket JSON assumption is encoded in comments and jq parsing (`bin/niri-ctx:827-830`).
- Herdr `prefix+equal` rejected; config uses `prefix+v` and `prefix+minus` (`.config/herdr/config.toml:104-107`).
- Event-stream folded focus workaround: `WindowOpenedOrChanged` may include focus change, so watcher evaluates focus there too (`bin/niri-ctx:1305-1309`).
- `jq //` false workaround: `window_is_floating` avoids `//` because it would replace legitimate `false` (`bin/niri-ctx:939-946`).
- `wait_for_new_helium` binds `.id` before `index()` because jq function argument input surprised previous code (`bin/niri-ctx:313-323`).
- Top-follow disabled per user decision: config `TOP_FOLLOW=off`, install does not enable service (`.config/niri/contexts.conf:20`, `install.sh:62-68`, `.config/niri/WORKFLOW.md:187-198`).
- Admin has no devtools workspace; command silently no-ops (`bin/niri-ctx:1109-1111`).
- Declarative rules still match legacy per-role terminal app-ids even though current app-id is `*.work`, preserving compatibility with old windows (`.config/niri/cfg/rules.kdl:42-65`).
- Layer regex `^noctalia-wallpaper*` is likely intentionally loose but is not fully anchored and `*` applies only to preceding `r` in regex syntax (`.config/niri/cfg/rules.kdl:80-82`).

## 11. Brittle Areas and Likely Bugs

- `ctx_repo_specs` and config explicitly disallow spaces in paths; Bash word splitting would break any repo dir with spaces (`.config/niri/contexts.conf:1-3`, `bin/niri-ctx:135-140`).
- `MAIN_OUTPUT`, `TOP_OUTPUT`, and `COMMS_OUTPUT` have no script-side defaults; absent config variables can trip `set -u` when paths execute.
- `TOP_FOLLOW` default in code is `devtools`, while config/docs say disabled; removing the config line would re-enable watcher behavior if the service is active (`bin/niri-ctx:1245`, `.config/niri/contexts.conf:20`).
- Event-stream waits can miss windows if the event arrives before subscription starts; there is no final poll fallback in `ctx_wait_window` (`bin/niri-ctx:281-325`, `bin/niri-ctx:415-418`, `bin/niri-ctx:465-466`).
- `wait_for_app_id` accepts matches from `WindowsChanged` snapshots, so for non-unique app-ids it may return an existing window; this is okay for unique terminal app-ids but fragile for general use (`bin/niri-ctx:306-310`).
- Browser identity after cache loss is only “new Helium id not in before set”; it does not verify profile/window title (`bin/niri-ctx:441-477`).
- Browser cache validation trusts `app_id == "helium"` plus socket/id only; duplicate Helium windows are indistinguishable once cache is corrupted or stale (`bin/niri-ctx:327-353`).
- `pkill -f` class regex could kill unrelated processes with similar command lines (`bin/niri-ctx:423-433`).
- Global lock requires `flock`, but doctor does not check for `flock`; missing `flock` would break mutating commands (`bin/niri-ctx:1195-1203`, `bin/niri-ctx:1403-1410`).
- Watcher relies on Bash dynamic scoping for `WIN_APP`, `WIN_WS`, `WS_NAME`, `WS_OUTPUT`, and `WATCH_IGNORE_UNTIL` between `watch_daemon` and helper functions (`bin/niri-ctx:1212-1260`, `bin/niri-ctx:1272-1276`).
- `ctx_focus_workspace` silently returns if target workspace is absent, so missing workspace declarations can degrade into no-op rather than hard failure (`bin/niri-ctx:229-235`).
- Many layout actions are best-effort `|| true`; convergence can silently fail under Niri IPC/layout timing changes (`bin/niri-ctx:402`, `452`, `472`, `506`, `1001`, `1030`, `1043`, `1052`, `1085`, `1113`, `1143`).
- Herdr socket commands all use `timeout 2`; slow Herdr responses cause silent no-op convergence (`bin/niri-ctx:626-630`).
- Herdr session valid regex only permits alphabetic context prefixes; current contexts fit, future context names with digits/hyphens would fail (`bin/niri-ctx:608-612`).
- `repo:<label>` normalization lowercases labels, so mixed-case repo labels in `CTX_REPOS` would not match (`bin/niri-ctx:109-123`, `.config/niri/contexts.conf:7-11`).
- Docs are stale in several places: `CTX_DIR` instead of `CTX_REPOS`, old five-card order, old Herdr session names `<ctx>-dev/-agents/-logs/-terminal`, and stale hotkey numbering (`.config/niri/WORKFLOW.md:79-89`, `131-145`, `210-219`).

## 12. Behaviors to Preserve vs Drop

### Preserve exactly

- CLI shape used by keybinds/autostart/systemd/tests: `open`, `scratch`, `comms`, `devtools-here`, `top-ambient`, `spotify`, `watch`, `startup`, `doctor`, `--tmux-role` (`bin/niri-ctx:28-41`, `.config/niri/cfg/keybinds.kdl:87-120`, `.config/niri/cfg/autostart.kdl:5`, `.config/systemd/user/niri-ctx-watch.service:8`).
- Context aliases `job1/job2/side1/side2` and role aliases (`bin/niri-ctx:76-87`, `bin/niri-ctx:109-126`).
- Guarded focus semantics to avoid workspace back-and-forth (`bin/niri-ctx:218-247`).
- Global lock and focus-only fallback for concurrent invocations (`bin/niri-ctx:1153-1203`).
- Helium cache file format and path, including `NIRI_SOCKET` validation (`bin/niri-ctx:263-266`, `bin/niri-ctx:327-360`; tests read `~/.cache/niri-ctx/browser-up-docs.id` at `tests/converge.sh:33-37`).
- Deterministic oldest-window selection by lowest id for duplicate app-ids (`bin/niri-ctx:249-255`).
- Current two-card context open: docs column `1`, work terminal column `2`, final focus docs (`bin/niri-ctx:538-554`; asserted by `tests/converge.sh:40-52`, `tests/converge.sh:146-150`).
- Re-home drifted docs/work/comms/Spotify windows to canonical workspaces (`bin/niri-ctx:397-407`, `bin/niri-ctx:447-457`, `bin/niri-ctx:980-1004`, `bin/niri-ctx:1132-1145`).
- Flatten tracked project cards without disturbing non-card stacks (`bin/niri-ctx:509-536`).
- Comms convergence to one stacked column for present tiled Slack/Telegram/Discord windows (`bin/niri-ctx:980-1055`; asserted by `tests/converge.sh:120-130`).
- Spotify re-home to `top-ambient` (`bin/niri-ctx:1132-1146`; asserted by `tests/converge.sh:134-144`).
- Herdr repo-major layout and migration from legacy `editor` workspace (`bin/niri-ctx:640-697`; asserted by `tests/converge.sh:107-118`).
- Role deep-links land on current repo’s role tab (`bin/niri-ctx:699-758`; asserted by `tests/converge.sh:112-118`).
- No Admin devtools (`bin/niri-ctx:1109-1111`).
- Watcher remains opt-in/disabled by config/install unless user changes it (`.config/niri/contexts.conf:20`, `install.sh:62-68`).

### Convergence test contract

`tests/converge.sh` canonical assertions:
- S1: `open UP` twice is idempotent; window count stable; UP docs/work on UP workspace; docs column `1`, work column `2` (`tests/converge.sh:80-86`).
- S2: if docs moved to `Webroot` and work to `Side`, `open UP` returns both to UP without changing window count and restores columns (`tests/converge.sh:88-95`).
- S3: if work is consumed into docs column, `open UP` expels/restores docs column `1`, work column `2` without changing window count (`tests/converge.sh:97-105`).
- S3b: Herdr `mono` workspace first three tabs are `editor agents logs`; legacy workspace labelled `editor` count is `0` (`tests/converge.sh:107-110`).
- S3c: `open UP repo:mono` focuses Herdr workspace `mono`; `open UP agents/logs/editor` focuses `mono/<role>` (`tests/converge.sh:112-118`).
- S4: if Slack exists and is exiled to UP, `niri-ctx comms` returns it to `comms` and comms apps occupy one unique column (`tests/converge.sh:120-130`).
- S5: if Spotify exists and is exiled to UP, `niri-ctx spotify` returns it to `top-ambient` (`tests/converge.sh:134-144`).
- S6: after `open UP`, focused Niri window is cached UP docs window (`tests/converge.sh:146-150`).

### Drop / legacy / vestigial

- Old frontend mode that auto-opened output browser and moved DevTools by title is removed; docs say removed 2026-07-04 (`.config/niri/WORKFLOW.md:250-257`, legacy behavior `legacy/niri-scripts/niri-frontend-mode:33-55`).
- Old smart-column left/right top-follow behavior is replaced by disabled watcher/top-follow (`legacy/niri-scripts/niri-smart-column-left:1-27`, `legacy/niri-scripts/niri-smart-column-right:1-27`, `bin/niri-ctx:1240-1260`).
- Legacy individual terminal cards `*.editor`, `*.agents`, `*.logs`, `*.term` should remain accepted by Niri rules only for existing windows, not recreated by new dispatcher (`.config/niri/cfg/rules.kdl:42-65`, `bin/niri-ctx:173-180`).
- Legacy browser cache files `~/.cache/niri-browser-*` are only warned about by doctor (`bin/niri-ctx:1463-1468`).
- Old `WORKFLOW.md` `CTX_DIR` section is stale; Rust port should use `CTX_REPOS` (`.config/niri/WORKFLOW.md:131-155`, `.config/niri/contexts.conf:6-12`).

## 13. Compatibility Surface

Hard dependencies that must not break:

- Installed executable path: `$HOME/.local/bin/niri-ctx`, symlinked by install and used by keybinds/autostart/systemd (`install.sh:22-25`, `.config/niri/cfg/keybinds.kdl:87-120`, `.config/niri/cfg/autostart.kdl:5`, `.config/systemd/user/niri-ctx-watch.service:8`).
- `niri-ctx open <context> [role]` with contexts `UP`, `Webroot`, `Sealant`, `Side`, `Admin`, `current`; aliases `job1`, `job2`, `side1`, `side2`; roles/aliases listed above (`bin/niri-ctx:28-41`, `bin/niri-ctx:76-126`).
- `niri-ctx scratch`, `comms`, `spotify`, `top-ambient`, `devtools-here`, `startup`, `watch`, `doctor` with no args (`bin/niri-ctx:1516-1559`).
- `niri-ctx --tmux-role <ctx> <role>` because terminal windows spawn it internally (`bin/niri-ctx:378`, `bin/niri-ctx:384`, `bin/niri-ctx:1507-1511`).
- Cache path and first-line id format for `~/.cache/niri-ctx/browser-up-docs.id`; tests read it directly (`tests/converge.sh:33-37`).
- Work terminal app-id `dev.yiannis.niri.<slug>.work`; tests locate UP work by `dev.yiannis.niri.up.work` (`tests/converge.sh:35-37`).
- Herdr socket path `$HOME/.config/herdr/sessions/UP-work/herdr.sock`; tests query it directly (`tests/converge.sh:55-78`).
- Herdr repo-major labels and tab labels `editor agents logs`; tests inspect them (`tests/converge.sh:70-78`, `tests/converge.sh:107-118`).
- Niri workspace names `scratch`, `Webroot`, `UP`, `Sealant`, `Side`, `Admin`, `top-ambient`, `*-devtools`, `comms` (`.config/niri/cfg/workspaces.kdl:5-51`).
- App-id identity for Helium `helium`, Slack `slack`, Telegram `org.telegram.desktop`, Discord `discord`, Spotify `Spotify` (`bin/niri-ctx:319-323`, `bin/niri-ctx:904-919`, `bin/niri-ctx:1118-1119`).
- Install expects `niri-ctx doctor` exit status to represent health (`install.sh:94-98`).

## 14. Risky Assumptions for Migration

- Rust port must replicate guarded focus ordering; naïve `focus-workspace` calls can trigger Niri workspace back-and-forth and change user-visible focus.
- Named workspace moves are part of correctness; adding `move-window-to-monitor` back can regress Spotify/devtools placement.
- Herdr behavior depends on 0.7.1 JSON response shapes and `w1`/`t1` fresh ids; changes in Herdr protocol need explicit version handling.
- The single work-card model is newer than docs; port should trust script/tests over `WORKFLOW.md` where they conflict.
- Event-stream timing is central to spawn waits; a Rust port should probably combine event subscription with polling to avoid current race windows while preserving timeouts.
- Browser identity is weak; improving it may change user expectations around existing cached Helium windows.
- Current commands are intentionally best-effort in many failure paths; turning every failed IPC action into a hard error may break workflows where convergence later self-heals.
- Paths in `CTX_REPOS` cannot contain spaces unless the config format changes.
- Output names are physical-machine-specific and assumed everywhere; Rust should keep them configurable and doctor should keep validating them.
- Watcher is implemented but disabled; porting it as enabled-by-default would conflict with current user decision.
- Test harness mutates live Niri state and directly depends on cache/session internals; migration should keep those internals or update tests in lockstep.
- `doctor` is both user health check and install gate; missing parity may make install look broken even if core commands work.
