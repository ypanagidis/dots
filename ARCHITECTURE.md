# ARCHITECTURE.md — niri-ctx Rust migration

Design for the Rust replacement of `bin/niri-ctx`. Grounded in `MIGRATION_AUDIT.md`
(behavior inventory) and `NIRI_IPC_NOTES.md` (IPC strategy; §9 review corrections
override §1–8). Read both before implementing.

## Goals / non-goals

Goals: typed, tested, observable replacement for the Bash dispatcher with the same
CLI surface and the same convergence semantics (`tests/converge.sh` S1–S6 is the
acceptance contract). Launch failures become visible and diagnosable.

Non-goals for v1: frontend mode (removed by user decision), enabling top-follow
(stays off), new workflow features, supporting terminals/browsers beyond what
config expresses, async runtime.

## Crate layout

Location: `rust/niri-ctx/` in this repo. Package name `niri-ctx`, binary target
`niri-ctx`; installed as `~/.local/bin/niri-ctx-rs` during the bridge phase
(install.sh handles naming), taking over the `niri-ctx` symlink at Phase 7.

Edition 2021. **Synchronous/blocking throughout** — this is a short-lived CLI;
`niri-ipc` ships a blocking `Socket` helper; the watcher (Phase 6) uses one thread
per socket. No tokio.

Dependencies (keep to this set unless something is genuinely missing):
`clap` (derive), `serde`, `serde_json`, `toml`, `niri-ipc = "=26.4.0"`,
`thiserror`, `anyhow`, `tracing`, `tracing-subscriber`, `rustix` (flock),
dev: `insta` (plan snapshots), `tempfile`.

```
rust/niri-ctx/src/
  main.rs           // arg parse → dispatch → exit code
  cli.rs            // clap definitions (surface below)
  config.rs         // TOML schema + loading + validation
  error.rs          // typed errors (thiserror); anyhow at the top level only
  logging.rs        // tracing init; file log + stderr on --verbose
  model.rs          // Context, Role, OutputRole, WorkspaceRef, WindowId, CardKind
  niri/
    mod.rs          // NiriClient trait + shared types (our own, NOT niri-ipc's)
    ipc.rs          // IpcNiriClient: niri-ipc Socket adapter; guarded-focus helpers
    fake.rs         // FakeNiriClient: scriptable state + recorded actions
  state.rs          // DesktopState snapshot built from workspaces+windows
  planner.rs        // pure: (config, state, goal) → Vec<Effect>
  executor.rs       // interprets Effects; owns IPC calls, spawning, waits, locking
  launcher.rs       // terminal/browser/comms-app launch + verify
  matchers.rs       // window identity (app-id, cache, before/after id sets)
  session.rs        // herdr/tmux convergence + deep-links (Phase 3/4)
  commands/
    mod.rs          // command → goal mapping; shared open/converge entry
    open.rs         // open <ctx> [role], scratch
    current.rs      // current (NEW)
    comms.rs        // comms
    devtools.rs     // devtools-here
    top_ambient.rs  // top-ambient, spotify
    startup.rs      // startup
    doctor.rs       // doctor [--json]
    inspect.rs      // inspect [--json] (NEW)
    plan.rs         // plan <command...> [--json] (NEW)
    watch.rs        // Phase 6 only
```

## CLI surface (preserved exactly + additions)

Preserved (keybinds/autostart/systemd/tests depend on these — byte-compatible):

```
niri-ctx open <UP|Webroot|Sealant|Side|Admin|current> [all|docs|output|editor|agents|logs|term|repo:<label>]
niri-ctx scratch | comms | spotify | top-ambient | devtools-here | startup | watch | doctor
niri-ctx --tmux-role <ctx> <role>     # internal terminal entrypoint
```

Context aliases (case-insensitive): up/job1→UP, webroot/job2→Webroot,
sealant/side1→Sealant, side/side2→Side, admin→Admin. Role aliases:
browser/browser-docs/docs→docs, browser-output/output→output,
shell/terminal/term→term, default all. `repo:<label>` lowercased,
`^[a-z0-9_-]+$`.

New: `current` (prints context name), `inspect [--json]`, `plan <command...>`,
global flags `--dry-run` (mutating commands print their plan and exit 0),
`--json` (inspect/doctor/plan), `--verbose`.

`--tmux-role` in Phase 1–4 execs the Bash implementation
(`exec bash bin/niri-ctx --tmux-role <ctx> <role>` via the repo path from config);
Rust-native herdr/tmux attach lands with session.rs and replaces the exec. This
keeps freshly spawned terminals working no matter which binary spawned them.

## Core model: plan → execute → re-observe, to a fixpoint

The Bash script's real semantics are *convergence*: every command drives the
world toward a canonical state from any start. Model that directly instead of
one linear plan:

```rust
loop (max CONVERGE_ITERS = 4):
    state = DesktopState::snapshot(client)          // workspaces + windows
    effects = planner::plan(&config, &state, &goal) // PURE
    if effects.is_empty() { break }                  // converged
    executor::run(effects)?                          // may spawn + wait
```

**Termination invariant (review finding #1 — load-bearing): the planner is
where ALL guards live.** It emits an effect only when the snapshot shows the
canonical state is violated: no `FocusWorkspace` if the target is already
focused, no `MoveWindowToWorkspace` if the window is already there, no
`MoveColumnToIndex` if the column index already matches, etc. A settled state
therefore yields an EMPTY plan and `open` converges in one iteration — this is
what makes `effects.is_empty()` a correct convergence test and makes the guard
logic (including the critical three-branch focus guard) unit-testable as pure
planner branches. The client additionally re-checks live state immediately
before focus actions purely as a race-safety net (focus-follows-mouse can move
focus between snapshot and action); that re-check is a secondary defense, never
the primary guard.

Planner purity is the testability win: every branch is a unit test on
`(config, fake state, goal) → effects`, and `--dry-run`/`plan` print iteration 1
of the loop. Spawn-dependent steps (move/flatten a window that doesn't exist
yet) are NOT special-cased — the spawn happens in iteration 1, the wait-for-map
verifies it, and iteration 2's fresh snapshot plans the placement. The iteration
cap turns non-convergence into a hard, diagnosable error instead of a silent
half-state.

### Effects

```rust
enum Effect {
    // niri actions (executor maps 1:1 onto NiriAction). The planner emits each
    // of these ONLY when the snapshot shows it is needed (see termination
    // invariant above) — there are no "IfNeeded" effects; the plan itself is
    // the guard's output.
    FocusOutput { output: OutputName },
    FocusWorkspace { output: OutputName, ws: WorkspaceRef },
    FocusWindow { id: WindowId },
    MoveWindowToWorkspace { id: WindowId, ws: WorkspaceRef, focus: bool },
    MoveColumnToIndex { index: usize },                  // acts on focused column → PLANNER emits the pairing FocusWindow first
    ExpelWindowFromColumn,                                // acts on focused window
    ConsumeWindowIntoColumn,
    SetColumnWidth { change: SizeChange },
    SetWindowHeight { id: WindowId, change: SizeChange },
    // process world
    SpawnTerminal { ctx: Context, role: Role, app_id: String, title: String },
    SpawnBrowser { ctx: Context, role: BrowserRole, profile: String },
    SpawnCommsApp { app: CommsApp },
    SpawnSpotify,
    // verification / bookkeeping
    WaitForWindow { matcher: WindowMatcher, timeout: Duration, on_fail: LaunchFailure },
    WriteBrowserCache { ctx_slug: String, role: BrowserRole, id: WindowId },
    Log { level: Level, msg: String },
    Fail { diag: Diagnostic },                            // abort with actionable error
}
```

The three-branch focus guard from `bin/niri-ctx:229-247` is PLANNER logic:
emit nothing if the target workspace `is_focused`; emit `FocusOutput` only if
the target output is not focused; emit `FocusWorkspace` only if the target is
not already active-on-the-target-output. This is mandatory — naive
`focus-workspace` bounces via `workspace-auto-back-and-forth` — and living in
the planner makes all three branches pure unit tests. The client's live
re-check before focus actions is a race net only.

Column operations (`MoveColumnToIndex`, expel/consume) act on the *focused*
window/column in niri; the planner always emits the pairing `FocusWindow` first
(matching `bin/niri-ctx:505-506`, which is itself guarded to a no-op when the
column is already at the target index), and snapshot tests assert the pairing.

## NiriClient trait

```rust
trait NiriClient {
    fn workspaces(&mut self) -> Result<Vec<Workspace>>;
    fn windows(&mut self) -> Result<Vec<Window>>;
    fn action(&mut self, action: NiriAction) -> Result<()>;
    fn wait_for_window(&mut self, m: &WindowMatcher, timeout: Duration) -> Result<Option<Window>>;
}
```

`Workspace`/`Window`/`NiriAction` are OUR types in `niri/mod.rs`; `ipc.rs`
converts to/from `niri_ipc` types at the boundary (so a raw-JSON fallback stays
possible). Fields per NIRI_IPC_NOTES §1 — the used subset only: Workspace
{id, name, output, is_active, is_focused}; Window {id, title, app_id, pid,
workspace_id, is_focused, is_floating, column: Option<(usize, usize)>} (from
`layout.pos_in_scrolling_layout`). `SizeChange` re-exports the crate enum
(SetProportion etc. — NOT a string, see notes §9.4).

`wait_for_window` fixes the Bash race (audit §11) and needs TWO sockets — an
`EventStream` connection becomes a long-lived stream and cannot answer queries.
Concrete blocking implementation: (1) open a dedicated event socket and send
`EventStream` (subscription is now live); (2) spawn a short-lived reader thread
that lenient-decodes event lines and pushes matches onto an mpsc channel;
(3) on the main thread, immediately poll `windows()` on a separate command
socket (catches windows that mapped before subscription), then loop
`recv_timeout(500ms)` on the channel interleaved with a `windows()` re-poll,
until match or deadline. The reader thread exits on EOF/deadline; its socket is
dropped with it. Event decoding is lenient per notes §9.2: read the line, peek
the single top-level key, deserialize only known variants, log-and-skip unknown
ones — one unrecognized line must never kill a wait or the watcher.

`focused-window`/`focused-output` queries exist in niri but the tool derives
focus from `workspaces`/`windows` like Bash does — one snapshot, no extra
round-trips, and `DesktopState` stays the single source of truth.

## DesktopState

```rust
struct DesktopState {
    workspaces: Vec<Workspace>,           // + by_name (case-insensitive), by_id maps
    windows: Vec<Window>,                 // + by_id map
    focused_window: Option<WindowId>,
    focused_workspace: Option<WorkspaceId>,
    active_ws_by_output: HashMap<OutputName, WorkspaceId>,
}
impl DesktopState {
    fn current_context(&self, cfg: &Config) -> Option<&Context>;  // focused ws name, strip -devtools, fallback active-on-main
    fn oldest_window_by_app_id(&self, app_id: &str) -> Option<&Window>; // lowest id — deterministic
    fn tiled_on_workspace(&self, ws: WorkspaceId) -> Vec<&Window>;
    fn columns_on_workspace(&self, ws: WorkspaceId) -> BTreeMap<usize, Vec<&Window>>; // col → rows sorted
}
```

## Window identity (matchers.rs)

```rust
enum WindowMatcher {
    AppIdExact(String),                          // terminals: dev.yiannis.niri.<slug>.work
    NewAppIdExcluding { app_id: String, before: BTreeSet<WindowId> }, // helium spawn
    CachedId { id: WindowId, expect_app_id: String },
}
```

Terminal cards are matched by exact app-id (unique by construction). Browser
cards keep the Bash scheme exactly — same cache file
`~/.cache/niri-ctx/browser-<slug>-<role>.id` (line 1 window id, line 2
`$NIRI_SOCKET`; atomic write via temp+rename), same validation (uint id, socket
matches, window exists, app_id == "helium"), same before/after id-set match for
new spawns. converge.sh reads this file directly; do not change the format.
Weighted multi-signal matching (title markers, pid) is a later, optional
improvement — do not build it in Phase 1–3.

## Launcher (launcher.rs)

Terminal: build argv from config (`alacritty --class <id>,<id> --title <t> -e
<niri-ctx-path> --tmux-role <ctx> <role>`; ghostty variant per audit §5; scratch
uses the PLAIN template — no `-e` entrypoint, ghostty takes `--title=` equals
form per `bin/niri-ctx:1069-1073`). Spawn with `pre_exec(setsid)` but keep the
process a DIRECT child (no double-fork — unlike Bash's `setsid -f`) so its exit
status is observable via `try_wait`; then `WaitForWindow(app_id, timeout 10s)`.

Launch failure has two DISTINCT diagnosable states (review finding #3):
(a) **process exited** — `try_wait` yields the code: report command, pid, exit
code, stderr tail if captured; (b) **process alive but window never mapped** —
the actual ghostty/VRAM failure mode, where there is no exit status by
definition: report "pid N alive, app-id X never appeared within Ns, attempt
M/2, killing via class match". On first failure: replicate the Bash self-heal —
pkill the exact class-marked command line, reap a herdr session the failed
launch created (fresh-session-only), retry once. On second failure return the
structured `LaunchFailure` for whichever state applies. Making state (b) loud
and precise is a primary migration motive (silent ghostty deaths).

Browser: Helium from config (`helium_bin`, `--profile-directory=<profile>
--new-window about:blank`), before/after id match, write cache, move to context
workspace.

All spawn commands come from config; nothing hardcoded beyond defaults generated
from the current setup.

## Config (config.rs)

Two-stage source of truth (review finding #5 — avoids two live configs during
the bridge):

- **Phases 1–6:** `contexts.conf` remains THE user-edited config, exactly as
  today. The Rust binary derives its config LIVE on each run by shelling out to
  bash (`bash -c 'source contexts.conf; declare -p CTX_REPOS ...'` — bash parses
  bash; no reimplementation), merged over built-in defaults and an optional
  `~/.config/niri-ctx/config.toml` for Rust-only keys (behavior flags, terminal
  templates). Editing `contexts.conf` affects both implementations immediately.
- **Phase 7:** `niri-ctx init-config` freezes the derived config into the full
  TOML below, which becomes the sole source of truth; `contexts.conf` is
  archived with the Bash script.

The TOML schema below is therefore the Phase-7 target AND the shape of the
in-memory `Config` struct from day one — only the loading path changes at
cutover. `doctor` validates whichever sources are active.

```toml
[outputs]
main = "DP-1"        # aliases main/top/vertical accepted wherever an output is named
top = "DP-2"
vertical = "HDMI-A-1"

[behavior]
session_backend = "herdr"        # herdr | tmux
top_follow = "off"                # off | devtools | ambient — stays off
launch_timeout_secs = 10
converge_iters = 4
bash_fallback = "/home/yiannis/Developer/Configs/bin/niri-ctx"  # for --tmux-role exec during bridge

[terminal]
program = "alacritty"             # alacritty | ghostty — selects both templates below
# fallback = "ghostty"            # optional second try after self-heal fails
# Two argv templates per program (built-in, overridable): "work" (with
# -e <niri-ctx> --tmux-role entrypoint) and "plain" (scratch: no entrypoint;
# ghostty needs --title= equals form). Placeholders: {app_id} {title} {ctx} {role}.

[browser]
bin = "/opt/helium-browser-bin/helium"

[[context]]
name = "UP"                       # workspace name == context name
slug = "up"                       # app-id segment
helium_profile = "Profile 1"
repos = [{ label = "mono", dir = "~/Developer/Work/UP/mono" }]  # first = default
# devtools workspace is <name>-devtools unless devtools = false
# ... Webroot, Sealant (2 repos), Side ...

[[context]]
name = "Admin"
slug = "admin"
repos = [{ label = "term", dir = "~" }]
devtools = false
terminal_role = "term"            # open all uses term, not editor

[comms]                            # order = column order top→bottom
# launch = LIST of candidate argvs; first whose binary exists wins
# (Bash tries Telegram then telegram-desktop — bin/niri-ctx:920-924)
apps = [
  { name = "slack",    app_id = "slack",                launch = [["slack"]] },
  { name = "telegram", app_id = "org.telegram.desktop", launch = [["Telegram"], ["telegram-desktop"]] },
  { name = "discord",  app_id = "discord",              launch = [["discord"]] },
]

[ambient]
spotify_app_id = "Spotify"
spotify_launch = [["spotify-launcher"], ["spotify"]]   # candidates, first found wins
```

Validation at load: output names non-empty, context names unique, repo dirs
exist (warn), slug matches `^[a-z0-9_-]+$`. Scratch is built-in (pseudo-context,
plain terminal `dev.yiannis.niri.scratch.term`, no herdr), not config.

## Locking & bridge compatibility

Same flock path as Bash: `${XDG_RUNTIME_DIR}/niri-ctx.lock` — Bash and Rust must
exclude each other during the bridge. Same semantics: nonblocking try; on
contention run focus-only recovery (guarded focus to the target workspace) and
exit 0. **The lock fd MUST be `O_CLOEXEC`** (review finding #4): Bash explicitly
closes fd 9 in its spawn subshell (`bin/niri-ctx:71`) for the same reason — a
spawned terminal/browser inheriting the lock fd holds the shared lock for its
whole lifetime and silently degrades every later command (Bash and Rust) to
focus-only recovery. Verify no spawned child inherits it. Same log file
`~/.cache/niri-ctx/log` (append, same rotation policy) so one tail shows both
implementations; tracing adds `--verbose` stderr output.

Shared contracts that must stay byte-compatible until Phase 7: browser cache
files, app-id scheme, herdr session/workspace/tab naming, flock path, exit codes
(0 success/lock-contention-recovered, nonzero on failure).

## Errors & observability

`error.rs`: `NiriCtxError` (thiserror) with variants Config, Ipc, LaunchFailed
{ command, app_id, cause }, NoConverge { command, iterations, remaining_effects },
UnknownContext, HerdrUnavailable... Top level prints one actionable line to
stderr (what failed, what was observed, what to try), full chain under
`--verbose`. `doctor` ports all 15 Bash checks (audit §1) plus: config
validity (derived + TOML), niri-ipc version handshake (`niri msg version` vs
pinned), lock-file accessibility, and that `behavior.bash_fallback` exists and
is executable (review finding #8 — every spawned terminal's argv embeds it
during the bridge; a stale path breaks all fresh terminals with no diagnostic).
`inspect --json` dumps DesktopState + resolved config. `plan <cmd>` prints
iteration-1 effects, `--json` for machine use.

## Test strategy

- Planner unit tests on hand-built `DesktopState`: every branch of open
  (fresh/idempotent/drifted/stacked → matches converge.sh S1–S3), comms (S4),
  spotify (S5), devtools-here (incl. Admin no-op), top-ambient, scratch,
  current-context inference, duplicate prevention, the **three focus-guard
  branches** (planner-pure per finding #1 — assert both the emitted effects AND
  the empty plan on settled state), missing-window → spawn+wait plan,
  launch-failure path.
- `insta` snapshot tests of plans for the canonical scenarios.
- Executor tests with FakeNiriClient recording actions (order-sensitive).
- **Convergence-loop integration test (Phase 3, mandatory):** a stateful
  FakeNiriClient that maps a window when it sees `SpawnTerminal`/`SpawnBrowser`;
  assert `open <ctx>` from empty state converges in ≤2 iterations and that a
  settled state converges in exactly 1 with an empty plan (this is the test
  class that catches termination bugs like review finding #1).
- config tests: TOML round-trip, live derivation from a fixture contexts.conf,
  init-config generation, validation failures.
- Live tests only behind `NIRI_CTX_LIVE_TESTS=1` (feature-gated ignore).
- `tests/converge.sh` (S1–S6 via `NIRI_CTX=<path>`) is the END-TO-END gate: it
  can only pass fully once mutation + session.rs land (Phases 3–4) and gates
  the Phase-7 cutover; Phase-1 planner tests cover iteration-1 plans only.

## Phase 1 implementation checklist (for the implementation agent)

1. Crate scaffolding, deps as listed, `cargo fmt`/`clippy -D warnings` clean.
2. cli.rs: full preserved surface + new commands; unknown command → same usage
   text style as Bash; `--tmux-role` execs `behavior.bash_fallback`.
3. config.rs (live contexts.conf derivation via bash shell-out + optional TOML
   overlay for Rust-only keys) + init-config + fixture-based tests.
4. model.rs/state.rs + context/role alias resolution + tests (audit §1 tables).
5. niri/mod.rs types + trait; ipc.rs read path (workspaces/windows via niri-ipc
   Socket, envelope per notes §9.3); fake.rs.
6. logging.rs, error.rs.
7. doctor (read-only, all checks), inspect, current, plan (planner may return
   only Log effects for not-yet-implemented goals — but implement the OPEN
   planner branches now since they're pure and testable; executor stays
   read-only/dry-run in Phase 1: mutating execution is Phase 3).
8. No mutating niri actions reachable in Phase 1 — executor refuses unless
   `plan`/`--dry-run` (prints) — this is a hard gate.
