# NIRI_IPC_NOTES.md

## 1. Installed Niri IPC surface

Installed compositor from the probe:

```text
niri 26.04 (8ed0da4)
NIRI_SOCKET=/run/user/1000/niri.wayland-1.1476.sock
```

### `niri msg` queries

Available `niri msg` commands in this install:

```text
outputs
workspaces
windows
layers
keyboard-layouts
focused-output
focused-window
pick-window
pick-color
action
output
event-stream
version
request-error
overview-state
casts
help
```

`--json` is available on `niri msg` and was used for all machine-readable captures.

### `niri msg action` actions

Available actions in 26.04, from the captured `niri msg action --help`:

```text
quit
power-off-monitors
power-on-monitors
spawn
spawn-sh
do-screen-transition
screenshot
screenshot-screen
screenshot-window
toggle-keyboard-shortcuts-inhibit
close-window
fullscreen-window
toggle-windowed-fullscreen
focus-window
focus-window-in-column
focus-window-previous
focus-column-left
focus-column-right
focus-column-first
focus-column-last
focus-column-right-or-first
focus-column-left-or-last
focus-column
focus-window-or-monitor-up
focus-window-or-monitor-down
focus-column-or-monitor-left
focus-column-or-monitor-right
focus-window-down
focus-window-up
focus-window-down-or-column-left
focus-window-down-or-column-right
focus-window-up-or-column-left
focus-window-up-or-column-right
focus-window-or-workspace-down
focus-window-or-workspace-up
focus-window-top
focus-window-bottom
focus-window-down-or-top
focus-window-up-or-bottom
move-column-left
move-column-right
move-column-to-first
move-column-to-last
move-column-left-or-to-monitor-left
move-column-right-or-to-monitor-right
move-column-to-index
move-window-down
move-window-up
move-window-down-or-to-workspace-down
move-window-up-or-to-workspace-up
consume-or-expel-window-left
consume-or-expel-window-right
consume-window-into-column
expel-window-from-column
swap-window-right
swap-window-left
toggle-column-tabbed-display
set-column-display
center-column
center-window
center-visible-columns
focus-workspace-down
focus-workspace-up
focus-workspace
focus-workspace-previous
move-window-to-workspace-down
move-window-to-workspace-up
move-window-to-workspace
move-column-to-workspace-down
move-column-to-workspace-up
move-column-to-workspace
move-workspace-down
move-workspace-up
move-workspace-to-index
set-workspace-name
unset-workspace-name
focus-monitor-left
focus-monitor-right
focus-monitor-down
focus-monitor-up
focus-monitor-previous
focus-monitor-next
focus-monitor
move-window-to-monitor-left
move-window-to-monitor-right
move-window-to-monitor-down
move-window-to-monitor-up
move-window-to-monitor-previous
move-window-to-monitor-next
move-window-to-monitor
move-column-to-monitor-left
move-column-to-monitor-right
move-column-to-monitor-down
move-column-to-monitor-up
move-column-to-monitor-previous
move-column-to-monitor-next
move-column-to-monitor
set-window-width
set-window-height
reset-window-height
switch-preset-column-width
switch-preset-column-width-back
switch-preset-window-width
switch-preset-window-width-back
switch-preset-window-height
switch-preset-window-height-back
maximize-column
maximize-window-to-edges
set-column-width
expand-column-to-available-width
switch-layout
show-hotkey-overlay
move-workspace-to-monitor-left
move-workspace-to-monitor-right
move-workspace-to-monitor-down
move-workspace-to-monitor-up
move-workspace-to-monitor-previous
move-workspace-to-monitor-next
move-workspace-to-monitor
toggle-debug-tint
debug-toggle-opaque-regions
debug-toggle-damage
toggle-window-floating
move-window-to-floating
move-window-to-tiling
focus-floating
focus-tiling
switch-focus-between-floating-and-tiling
move-floating-window
toggle-window-rule-opacity
set-dynamic-cast-window
set-dynamic-cast-monitor
clear-dynamic-cast-target
stop-cast
toggle-overview
open-overview
close-overview
toggle-window-urgent
set-window-urgent
unset-window-urgent
load-config-file
help
```

### JSON shape: `outputs`

`niri msg --json outputs` returns an object keyed by output name:

```rust
type Outputs = BTreeMap<String, Output>;

struct Output {
    name: String,
    make: String,
    model: String,
    serial: String,
    physical_size: [u32; 2],
    modes: Vec<Mode>,
    current_mode: u32,
    is_custom_mode: bool,
    vrr_supported: bool,
    vrr_enabled: bool,
    logical: LogicalOutput,
}

struct Mode {
    width: u32,
    height: u32,
    refresh_rate: u32,
    is_preferred: bool,
}

struct LogicalOutput {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    scale: f64,
    transform: String, // observed: "Normal", "180", "270"
}
```

### JSON shape: `workspaces`

`niri msg --json workspaces` returns `Vec<Workspace>`:

```rust
struct Workspace {
    id: u64,
    idx: u32,
    name: Option<String>,
    output: String,
    is_urgent: bool,
    is_active: bool,
    is_focused: bool,
    active_window_id: Option<u64>,
}
```

Important semantics from observed state:

- `is_focused` is global: only one workspace had it.
- `is_active` is per output: multiple workspaces can be active simultaneously, one per output.
- To detect “focused workspace per output,” use `output == target && is_focused`.
- To detect “active workspace on output,” use `output == target && is_active`.

### JSON shape: `windows` and `focused-window`

`niri msg --json windows` returns `Vec<Window>`. `niri msg --json focused-window` returns one `Window` object when a window is focused.

Observed shape:

```rust
struct Window {
    id: u64,
    title: String,
    app_id: String,
    pid: u32,
    workspace_id: u64,
    is_focused: bool,
    is_floating: bool,
    is_urgent: bool,
    layout: WindowLayout,
    focus_timestamp: FocusTimestamp,
}

struct WindowLayout {
    pos_in_scrolling_layout: Option<[u32; 2]>,
    tile_size: [f64; 2],
    window_size: [u32; 2],
    tile_pos_in_workspace_view: Option<[f64; 2]>,
    window_offset_in_tile: [f64; 2],
}

struct FocusTimestamp {
    secs: u64,
    nanos: u32,
}
```

Observed `pos_in_scrolling_layout` is `[column_index, row_index]` for tiled windows. The Bash script treats `null` as “not usable for column layout,” usually floating or otherwise outside the scrolling tiled layout.

### JSON shape: `focused-output`

`niri msg --json focused-output` returns one `Output` object with the same shape as values in `outputs`.

### Observed event stream event types

`niri msg --json event-stream` is line-oriented. The probe observed these event variants:

```json
{"WorkspacesChanged":{"workspaces":[...]}}
{"WindowsChanged":{"windows":[...]}}
{"KeyboardLayoutsChanged":{"keyboard_layouts":{"names":["English (US)"],"current_idx":0}}}
{"OverviewOpenedOrClosed":{"is_open":false}}
{"ConfigLoaded":{"failed":false}}
{"CastsChanged":{"casts":[]}}
{"WorkspaceActivated":{"id":15,"focused":true}}
{"WindowFocusChanged":{"id":38}}
```

Additional event variants already expected by `bin/niri-ctx` and part of the practical surface for the migration:

```rust
WindowOpenedOrChanged { window: Window }
WindowClosed { id: u64 }
```

The watcher explicitly handles focus changes folded into `WindowOpenedOrChanged.window.is_focused == true`, because a separate `WindowFocusChanged` may not arrive when focus changes at the same time as a title/workspace update.

## 2. IPC surface actually used today

The current Bash script uses only these Niri queries:

```text
niri msg --json workspaces
niri msg --json windows
niri msg --json event-stream
```

It does not currently call `outputs`, `focused-output`, or `focused-window`; it derives focused output/workspace/window state from `workspaces` and `windows`.

### Fields parsed from `workspaces`

Current jq usage requires:

```rust
Workspace {
    id,
    name,
    output,
    is_active,
    is_focused,
}
```

Specific uses:

- Find workspace id by case-insensitive name:
  `first(.[] | select((.name // "" | ascii_downcase) == target) | .id)`
- Find globally focused workspace name:
  `first(.[] | select(.is_focused) | .name // empty)`
- Find active workspace on an output:
  `first(.[] | select(.output == output and .is_active) | .name)`
- Check output exists:
  `any(.[]; .output == output)`
- Check output is focused:
  `any(.[]; .output == output and .is_focused)`
- Watcher cache:
  `.WorkspacesChanged.workspaces[] | [.id, (.name // ""), (.output // "")]`

### Fields parsed from `windows`

Current jq usage requires:

```rust
Window {
    id,
    app_id,
    workspace_id,
    is_focused,
    is_floating,
    layout: WindowLayout {
        pos_in_scrolling_layout,
    },
}
```

The script also reads `title` indirectly only for human context in probe/logs, not for decisions.

Specific uses:

- Find deterministic window by app id:
  `[.[] | select(.app_id == app_id) | .id] | sort | first`
- Validate cached browser window:
  `id == cached && app_id == "helium"`
- Snapshot existing Helium ids before spawn.
- Find a window’s `workspace_id`.
- Find a window’s column:
  `.layout.pos_in_scrolling_layout[0]`
- Find tiled windows on a workspace:
  `workspace_id == ws && is_floating == false && layout.pos_in_scrolling_layout != null`
- Detect stacked columns:
  group by `layout.pos_in_scrolling_layout[0]`, sort by row index.
- Detect right column’s first window:
  sort by column index, then row index.
- Detect focused window for `devtools-here`:
  `first(.[] | select(.is_focused) | .id)`

### Events parsed from `event-stream`

The Bash watcher and wait helpers require:

```rust
enum NiriEvent {
    WorkspacesChanged { workspaces: Vec<Workspace> },
    WindowsChanged { windows: Vec<Window> },
    WindowOpenedOrChanged { window: Window },
    WindowClosed { id: u64 },
    WindowFocusChanged { id: Option<u64> }, // observed id was numeric
}
```

The script ignores but must tolerate:

```rust
KeyboardLayoutsChanged { keyboard_layouts: serde_json::Value },
OverviewOpenedOrClosed { is_open: bool },
ConfigLoaded { failed: bool },
CastsChanged { casts: Vec<serde_json::Value> },
WorkspaceActivated { id: u64, focused: bool },
```

### Actions actually used today

Current `niri_action` call sites:

```text
focus-monitor <output>
focus-workspace <reference>
focus-window --id <window_id>
move-window-to-workspace --window-id <window_id> --focus false <reference>
move-column-to-index <index>
expel-window-from-column
set-column-width <change>
consume-window-into-column
set-window-height --id <window_id> <change>
```

No current `niri msg action spawn` call exists. Process spawning is done outside Niri with `setsid -f`, then correlated by app-id through `windows` and `event-stream`.

`move-workspace-to-index` is not currently called by `bin/niri-ctx`, but it is required by the live-workspace ordering gotcha below.

### Minimal Rust-ish surface

Use this as the migration target instead of binding the entire Niri API directly into planner code:

```rust
#[async_trait]
trait NiriClient {
    async fn workspaces(&self) -> Result<Vec<Workspace>>;
    async fn windows(&self) -> Result<Vec<Window>>;
    async fn events(&self) -> Result<NiriEventStream>;

    async fn action(&self, action: NiriAction) -> Result<()>;

    async fn focus_output_if_needed(&self, output: &str) -> Result<()>;
    async fn focus_workspace_if_needed(&self, output: &str, workspace: WorkspaceRef) -> Result<()>;
    async fn focus_window(&self, id: WindowId) -> Result<()>;

    async fn move_window_to_workspace(
        &self,
        window: WindowId,
        workspace: WorkspaceRef,
        focus: bool,
    ) -> Result<()>;

    async fn move_column_to_index(&self, index: u32) -> Result<()>;
    async fn move_workspace_to_index(
        &self,
        workspace: Option<WorkspaceRef>,
        index: u32,
    ) -> Result<()>;

    async fn expel_window_from_column(&self) -> Result<()>;
    async fn consume_window_into_column(&self) -> Result<()>;
    async fn set_column_width(&self, change: SizeChange) -> Result<()>;
    async fn set_window_height(&self, id: WindowId, change: SizeChange) -> Result<()>;

    // Optional v1 helper only if switching from external setsid spawning:
    async fn spawn(&self, command: Vec<String>) -> Result<()>;
}

enum NiriAction {
    FocusMonitor { output: String },
    FocusWorkspace { reference: WorkspaceRef },
    FocusWindow { id: WindowId },
    MoveWindowToWorkspace {
        window_id: WindowId,
        reference: WorkspaceRef,
        focus: bool,
    },
    MoveColumnToIndex { index: u32 },
    MoveWorkspaceToIndex {
        reference: Option<WorkspaceRef>,
        index: u32,
    },
    ExpelWindowFromColumn,
    ConsumeWindowIntoColumn,
    SetColumnWidth { change: SizeChange },
    SetWindowHeight { id: Option<WindowId>, change: SizeChange },
    Spawn { command: Vec<String> },
}

enum WorkspaceRef {
    Index(u32),
    Name(String),
}

struct SizeChange(String); // examples: "100%", "33%", "+10%", "-10%", "1000"
struct WindowId(u64);
```

Match these to real Niri action names:

- `FocusOutput` in planner terms maps to Niri `focus-monitor`.
- `FocusWorkspace { reference }` maps to `focus-workspace`.
- `FocusWindow { id }` maps to `focus-window --id`.
- `MoveWindowToWorkspace` maps to `move-window-to-workspace --window-id --focus <bool> <reference>`.
- `MoveWorkspaceToIndex` maps to `move-workspace-to-index [--reference <workspace>] <index>`.
- `SetColumnWidth` maps to `set-column-width <change>`.
- `SetWindowHeight` maps to `set-window-height [--id <window>] <change>`.
- `Spawn` maps to `spawn <COMMAND>...`, but current Bash does not depend on it.

## 3. `niri-ipc` crate decision

The probe’s crates.io metadata:

```json
{
  "max_version": "26.4.0",
  "versions": [
    "26.4.0",
    "25.11.0",
    "25.8.0",
    "25.5.1",
    "25.5.0",
    "25.2.0",
    "25.1.0",
    "0.1.10"
  ]
}
```

Installed Niri is `26.04`, and the matching crate is published as `26.4.0`. The probe explicitly notes that `niri` and `niri-ipc` are published in lockstep from the same repo/release.

Recommendation for v1: use a pinned crate dependency:

```toml
niri-ipc = "=26.4.0"
```

Rationale:

- There is an exact crate match for the installed compositor.
- The crate already defines the request/reply/action/event serde shapes, reducing local protocol drift.
- Niri IPC is versioned/release-coupled rather than a broad stable protocol. Exact pinning is the correct default.
- Maintenance cost is lower than hand-maintaining raw serde enums for every action variant.
- The application should still hide this behind its own `NiriClient` trait, because the planner only needs the narrow surface above.
- If a future Niri upgrade changes IPC, the failure should be localized to the adapter and surfaced by a startup `version` check.

No explicit raw protocol compatibility handshake was visible in the probe. Treat the running compositor version and the pinned crate version as the compatibility check.

Do not expose `niri-ipc` types throughout the planner. Keep them at the boundary.

## 4. Wire protocol notes

Niri IPC uses `$NIRI_SOCKET`, a Unix domain socket. The CLI’s JSON output is not the raw reply; `niri msg --json windows` unwraps the relevant reply payload and prints only the window list.

Practical model:

- Normal request/reply commands open a socket connection, send one JSON request, receive one JSON reply, then finish.
- `event-stream` opens a long-lived socket connection.
- Event stream replies are newline-delimited JSON events, one event per line.
- On compositor restart, the event stream reaches EOF or errors; reconnect using the new `$NIRI_SOCKET` environment if the process was relaunched in a fresh environment, or exit/restart the watcher service.

The raw serde shape used by `niri-ipc` is Rust enum JSON. Unit requests are string-like enum variants, and data-carrying requests/replies/events are externally tagged objects. Observed event examples prove the externally tagged event shape:

```json
{"WindowFocusChanged":{"id":38}}
```

Use the crate for exact request/action encoding. If implementing raw JSON anyway, add tests against the crate’s serde output for every request variant used.

## 5. Known behavioral gotchas the Rust planner must encode

These are verified on this machine and should be carried forward as planner invariants:

1. `workspace-auto-back-and-forth` applies to scripted `focus-workspace`.
   Focusing an already-focused workspace bounces back to the previous workspace. Every workspace focus must be guarded by a state check:
   - If target workspace has `is_focused == true`, do nothing.
   - Focus the target output first only if needed.
   - Call `focus-workspace` only when target is not active on the intended output or is on a different output.

2. Never call `move-window-to-monitor` after moving a window to a named workspace.
   Moving to the named workspace is sufficient. A follow-up monitor move re-moves the window onto that output’s currently active workspace.

3. Window-rule app-id regexes are unanchored.
   Always anchor app-id rules with `^...$` unless substring matching is intentional.

4. Niri does not reorder existing named workspaces on config reload.
   Use `move-workspace-to-index` live when the desired order matters.

5. Window id caches must be scoped to the compositor instance.
   The Bash cache stores the `NIRI_SOCKET` beside ids because window ids restart after compositor restart.

6. JSON order for `windows` is not stable.
   For duplicate app ids, current behavior picks the lowest id for deterministic “oldest” selection.

## 6. API gaps / limitations relevant to planned features

### Comms column arrangement

Target behavior: Slack, Telegram, Discord stacked vertically in one full-width column with roughly equal heights.

Useful actions exist:

```text
focus-window --id <id>
move-window-to-workspace --window-id <id> --focus false <workspace>
move-column-to-index <index>
set-column-width "100%"
consume-window-into-column
expel-window-from-column
set-window-height --id <id> "<percent>%"
move-column-to-workspace <reference>
move-column-to-monitor <output>
```

What the planner can do:

- Move each comms app to the `comms` workspace.
- Ensure each app is not floating.
- Flatten existing multi-window columns by focusing the bottom tracked/tiled window and calling `expel-window-from-column`.
- Move singleton columns into deterministic order.
- Focus the first column and repeatedly `consume-window-into-column` from the right.
- Set each tracked window height to `100 / count`.

What cannot be fully guaranteed:

- Exact equal pixel heights. `set-window-height` is a request into Niri’s layout engine; borders, gaps, constraints, app minimum sizes, and rounding can affect final sizes.
- Atomic arrangement. Layout updates can lag, so the Bash implementation re-reads windows and retries briefly.
- Arrangement of floating windows. Current code skips floating windows for stacking.
- Disturbance-free stacking if unrelated windows are in the same workspace/columns. Current code tries to flatten only tracked cards for context workspaces, but comms flattening breaks every multi-window tiled column on that workspace because it assumes comms owns that workspace.

### Focusing outputs/workspaces without side effects

There is no side-effect-free `focus-workspace` when `workspace-auto-back-and-forth` is enabled. The Rust client must implement guarded focus as a higher-level operation using `workspaces()` first.

`focus-monitor` is safer but still changes focus. Guard it by checking whether any workspace on that output has `is_focused`.

### Detecting focused workspace per output

Use `workspaces`:

- Focused output: workspace where `is_focused == true`; its `output` is the focused output.
- Active workspace on an output: workspace where `output == target && is_active`.
- Focused workspace on a specific output: workspace where `output == target && is_focused`.

Do not confuse `is_active` with global focus. There are multiple active workspaces, one per output.

### Spawn and process/window correlation

Current Bash does not use Niri’s `spawn` action. It spawns processes externally and correlates windows by app-id through `windows` and `event-stream`.

Niri’s `spawn` action is available, but the probe does not show it returning a spawned pid. Plan as if `spawn` returns only action success/failure, not a process id or window id.

For reliable correlation:

- Prefer launching apps with deterministic app ids/classes where possible.
- Snapshot existing matching window ids before spawn when app ids are shared, as done for Helium.
- Wait on `WindowsChanged` or `WindowOpenedOrChanged`.
- Validate by `app_id`, and for duplicates choose deterministic id order or use a before/after id set.

## 7. Recommended two-socket watcher model

Use two independent IPC paths:

1. Watch socket:
   - Long-lived `event-stream`.
   - Reads one JSON event per line.
   - Maintains local caches for windows and workspaces.
   - On EOF/error, drops all cache state, backs off, reconnects, and waits for fresh `WorkspacesChanged`/`WindowsChanged`.

2. Command socket:
   - Short-lived request/reply connections for actions and queries.
   - Used by planner operations such as guarded focus, re-home, arrange comms, and doctor checks.
   - Do not multiplex actions onto the event-stream connection.

On Niri restart:

- Expect window ids to be invalid.
- Clear caches.
- Reconnect event stream.
- Re-run initial `workspaces()` and `windows()` snapshots before applying planner actions.
- Treat stale cache files from a different `NIRI_SOCKET` as invalid.

## 8. Example typed requests

These examples show the intended typed IPC operations. Exact raw serialization should come from `niri-ipc = "=26.4.0"`.

### Query workspaces

Request:

```json
"Workspaces"
```

Reply payload, as unwrapped by `niri msg --json workspaces`:

```json
[
  {
    "id": 11,
    "idx": 1,
    "name": "comms",
    "output": "HDMI-A-1",
    "is_urgent": false,
    "is_active": true,
    "is_focused": true,
    "active_window_id": 11
  }
]
```

### Focus a window by id

Typed request:

```rust
Request::Action(Action::FocusWindow { id: Some(11) })
```

CLI equivalent:

```text
niri msg action focus-window --id 11
```

Expected reply: success/empty OK. The CLI discards it with `>/dev/null`.

### Move a window to a named workspace without focusing it

Typed request:

```rust
Request::Action(Action::MoveWindowToWorkspace {
    window_id: Some(11),
    reference: WorkspaceReference::Name("comms".into()),
    focus: false,
})
```

CLI equivalent:

```text
niri msg action move-window-to-workspace --window-id 11 --focus false comms
```

Expected reply: success/empty OK.

### Set a specific window height

Typed request:

```rust
Request::Action(Action::SetWindowHeight {
    id: Some(11),
    change: "33%".into(),
})
```

CLI equivalent:

```text
niri msg action set-window-height --id 11 33%
```

Expected reply: success/empty OK.

### Event stream line

Observed event line:

```json
{"WindowFocusChanged":{"id":38}}
```

Observed initial snapshot lines on a new event stream:

```json
{"WorkspacesChanged":{"workspaces":[{"id":11,"idx":1,"name":"comms","output":"HDMI-A-1","is_urgent":false,"is_active":true,"is_focused":true,"active_window_id":11}]}}
```

```json
{"WindowsChanged":{"windows":[{"id":11,"title":"@Ekon - Discord","app_id":"discord","pid":5488,"workspace_id":11,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[1,3],"tile_size":[940.0,731.3333333333334],"window_size":[940,731],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]},"focus_timestamp":{"secs":11743,"nanos":443062879}}]}}
```
## 9. Review corrections (opus-4.8 adversarial review, 2026-07-05)

Verdict on sections 1-8: **sound-with-fixes**. The pinned-crate recommendation, the two-socket watcher model, and the derived action/query surface were verified complete against bin/niri-ctx (every call site cross-checked) and the live probe. The following corrections OVERRIDE the corresponding statements above; implementers must apply them.

### 9.1 Licensing (major)

`niri-ipc` 26.4.0 is **GPL-3.0-or-later** (verified on crates.io). Linking it makes the niri-ctx binary a derivative work distributable only under GPL-3.0. For private use nothing is triggered, but this dotfiles repo is public-looking and currently has no LICENSE file. Decision required, deliberately, not by default:
- Option A: accept GPL-3.0 for the Rust crate (fine for a personal tool; add a note/LICENSE).
- Option B: hand-roll the ~10 small serde types over $NIRI_SOCKET (the surface in §2 is tiny) to stay license-free.
Either way the `NiriClient` trait boundary makes the choice reversible.

### 9.2 Event enum forward-compat (major)

The crate's `Event` enum in 26.4.0 has **19 variants** and is **NOT `#[non_exhaustive]`** — deserialization is strict. The "must tolerate" list in §1 is illustrative, not exhaustive; a 3s idle probe simply didn't see `WindowLayoutsChanged` (fires on the very resizes/column moves comms convergence performs), `WorkspaceActiveWindowChanged`, `WindowUrgencyChanged`, `WorkspaceUrgencyChanged`, `WindowFocusTimestampChanged`, `KeyboardLayoutSwitched`, `ScreenshotCaptured`, `CastStartedOrChanged`, `CastStopped`.

Requirement: the watcher must decode event lines **leniently** — parse the tag (`keys[0]`, as Bash does today) and route known variants; log-and-skip unknown ones. Never let one unrecognized line (e.g. after a compositor upgrade) kill the stream. Do not deserialize the stream directly into the crate's `Event` in one strict step.

### 9.3 Raw wire envelope (fills a gap in §4)

The raw reply on the socket is **double-tagged** — `Reply = Result<Response, String>`:
- success: `{"Ok":{"Workspaces":[...]}}` (or `{"Ok":"Handled"}` for actions — externally tagged `Response`)
- error: `{"Err":"message"}`

`niri msg --json` prints the UNWRAPPED payload, so §8's bare-array examples are CLI output, not wire bytes. An `EventStream` request gets a single `{"Ok":"Handled"}` reply line, then newline-delimited `Event` JSON, one per line, on the same long-lived connection. Request/reply commands: one JSON request line per connection. The crate handles the envelope automatically; only a raw-JSON implementation needs to parse it (and should test its serde against the crate's output).

### 9.4 Typed-example fixes (§2/§8 used wrong crate types)

- `Action::FocusWindow { id: u64 }` — the field is not `Option`: `FocusWindow { id: 11 }`.
- The workspace reference argument type is `WorkspaceReferenceArg`, not `WorkspaceReference`.
- `SizeChange` is an **enum**, not a string wrapper: `SetFixed(f64) | SetProportion(f64) | AdjustFixed(i32) | AdjustProportion(f64)`. CLI `"33%"` corresponds to `SizeChange::SetProportion(33.0)`. Re-export/use the crate's enum; do not model it as `SizeChange(String)`.
- `MoveColumnToIndex` / `MoveWorkspaceToIndex` use `index: usize` in the crate (trait sketch said u32 — harmless, but match the crate at the boundary).
- Keep `set-window-height`'s id `Option<u64>` at the enum/adapter boundary (focused-window form exists) even though the planner always passes an explicit id.
- Shape nits on queries the script does not use: `Output.current_mode` is `Option<usize>`, and `LogicalOutput.transform` is a `Transform` enum (serialized as the observed strings), not a bare `String`.

### 9.5 Gotcha clarifications

- Gotcha #1 (guarded focus) must replicate the script's exact three branches (bin/niri-ctx:229-247): early-return if target workspace `is_focused`; `focus-monitor` only if the target output is not already focused; `focus-workspace` only if the target is not already active-on-the-intended-output.
- Gotcha #4 (`move-workspace-to-index` for live workspace ordering) is **aspirational** — the Bash script never calls it. Include it in the action enum, but label the behavior "planned", not "carried over".
