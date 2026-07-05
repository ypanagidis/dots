# WATCHER_DESIGN.md — `niri-ctx watch` (Phase 6)

Design for the Rust port of the Bash `watch_daemon` (`bin/niri-ctx:1210-1329`).
Grounded in ARCHITECTURE.md (blocking/threads, `NiriClient` trait, lenient
decode), MIGRATION_AUDIT.md §1 (`watch`) / §9 (systemd), NIRI_IPC_NOTES.md §7
(two-socket model) / §9.2 (lenient decode mandatory).

## Ground rules (hard constraints — do not relax)

- **Disabled by default.** `TOP_FOLLOW=off` and the systemd unit stays unlinked.
  `install.sh` must never enable it. The watcher does nothing user-visible when
  `top_follow == "off"` — it still connects and maintains caches, but
  `watch_consider_focus` returns immediately (mirrors `bin/niri-ctx:1245`).
- **Optional.** Every other `niri-ctx` command is fully useful with no watcher
  running. The watcher only *adds* top-follow; it owns no state anything else
  depends on.
- **Blocking/threads only.** No tokio. Two threads total: one event reader, the
  main loop. Two independent sockets (NIRI_IPC_NOTES §7).

## 1. Process model & ownership

`niri-ctx watch` is a long-running foreground process. Preflight (port
`bin/niri-ctx:1264-1271`): if `NIRI_SOCKET` is unset or `workspaces()` fails,
log one line and `exit 0` (quiet, not an error — nothing to watch).

Two threads, each owning exactly one thing; no shared mutable state (this
deliberately removes the Bash dynamic-scoping fragility flagged in audit §11):

```
 event socket (long-lived)          command socket (short-lived req/reply)
        │                                   ▲
   [reader thread]                          │
   read_line → lenient decode          [main thread]
        │  WatchMsg                     owns caches + ignore_until + debounce
        └────── mpsc::Sender ──────────►recv_timeout → apply → (maybe) top-follow
```

- **Reader thread** owns the event `UnixStream` only. Loop `read_line`; for each
  line, tag-peek + decode (see §2) into `WatchMsg` and `send()` it. On EOF or
  read error it sends `WatchMsg::Disconnected(reason)` and returns; the socket
  drops with the thread. It never touches caches and never issues actions — pure
  decode+forward. One malformed/unknown line is logged and skipped, never fatal.
- **Main thread** owns the caches, an `IpcNiriClient` command socket, the
  `ignore_until: Instant` suppression clock, and the debounce buffer. It is the
  only thing that reads caches or issues niri actions. It blocks on
  `rx.recv_timeout(debounce_tick)`.

```rust
enum WatchMsg {
    Workspaces(Vec<Workspace>),        // full snapshot → rebuild ws cache
    Windows(Vec<Window>),              // full snapshot → rebuild win cache
    WindowOpenedOrChanged(Window),     // fold one window; focus if is_focused
    WindowClosed(WindowId),
    WindowFocus(Option<WindowId>),
    Disconnected(String),              // reader is done; reconnect or exit
}
```

`mpsc` channel is unbounded — event volume is trivial and back-pressure is a
non-issue for a personal tool.

## 2. State model (caches) & lenient decode

Caches are the typed equivalent of the four Bash associative arrays
(`bin/niri-ctx:1272-1275`), held as plain fields on the main thread:

```rust
struct Caches {
    win: HashMap<WindowId, WinInfo>,      // WIN_APP + WIN_WS: { app_id, ws_id }
    ws:  HashMap<WorkspaceId, WsInfo>,    // WS_NAME + WS_OUTPUT: { name, output }
}
```

Fold rules (exact port of `bin/niri-ctx:1281-1322`):

- `Workspaces(v)` → **replace** the whole `ws` map from the snapshot.
- `Windows(v)` → **replace** the whole `win` map from the snapshot.
- `WindowOpenedOrChanged(w)` → upsert `win[w.id] = {w.app_id, w.workspace_id}`.
  Then, **if `w.is_focused == true`, run `consider_focus(w.id)`** — niri folds a
  focus change into this event when it coincides with a title/workspace change
  and no separate `WindowFocusChanged` follows (audit §10, NIRI_IPC_NOTES §1).
- `WindowClosed(id)` → `win.remove(id)`.
- `WindowFocus(Some(id))` → `consider_focus(id)`; `WindowFocus(None)` → ignore.

**Lenient decode (mandatory — NIRI_IPC_NOTES §9.2; the `Event` enum has 19
variants and is NOT `#[non_exhaustive]`).** Do NOT `serde_json::from_str::<Event>`
the whole line. Instead, exactly as Bash's `keys[0]` does and as the existing
`windows_from_event_line` (`rust/niri-ctx/src/niri/ipc.rs:189`) already does:

1. Parse the line to `serde_json::Value`; take the single top-level key (tag).
2. Match the tag against the five we act on (`WorkspacesChanged`,
   `WindowsChanged`, `WindowOpenedOrChanged`, `WindowClosed`,
   `WindowFocusChanged`), deserializing only that variant's payload into our own
   types (reusing the `From<niri_ipc::Window/Workspace>` converters).
3. Any other tag (`WindowLayoutsChanged`, `KeyboardLayoutSwitched`, casts, a
   future variant after a niri upgrade, …) → `trace!` and drop. Never fatal.
4. A payload that fails to deserialize → `debug!` and drop that line only.

This keeps the stream alive across compositor upgrades, which is the whole point
of §9.2.

## 3. Top-follow semantics (exact Bash port)

`consider_focus(focused_id)` reproduces `watch_consider_focus`
(`bin/niri-ctx:1240-1260`) exactly:

1. If `TOP_FOLLOW == off` → return. (Config key `behavior.top_follow`; default in
   code, matching Bash, is `devtools` if unset — but our shipped config sets
   `off`.)
2. If `Instant::now() < ignore_until` → return (self-induced-event window, §4).
3. If the global dispatcher lock is held → return (see handshake below).
4. Look up the focused window in caches: `app_id`, `ws_id` → `ws_name`,
   `ws_output`. Missing any → return.
5. If `ws_output != MAIN_OUTPUT` → return (only react to focus on the main
   carousel).
6. `ctx = Context::from_workspace_name(ws_name)` (strips `-devtools`); unknown →
   return; **`ctx == Admin` → return** (Admin has no devtools workspace).
7. Choose target:
   - `TOP_FOLLOW == devtools` **and** `app_id == "helium"` → `"<ctx>-devtools"`.
   - `TOP_FOLLOW == ambient` **and** `app_id != "helium"` → `"top-ambient"`.
   - otherwise no target → return.
8. `apply_top_follow(target)`.

`apply_top_follow(target)` reproduces `watch_apply_top_follow`
(`bin/niri-ctx:1225-1238`):

- Take a **fresh command-socket snapshot** (`workspaces()` + `windows()` →
  `DesktopState`). The event caches pick the *target*; the actual focus decision
  uses live state so it can never fight a race. If the workspace active on
  `TOP_OUTPUT` is already `target`, return (Bash's early `==` check).
- Set `ignore_until = Instant::now() + 700ms` **before** issuing focus, so the
  focus we are about to cause does not re-enter `consider_focus`.
- Emit `focus_workspace_guarded(&state, TOP_OUTPUT, target)` (§7) then
  `FocusMonitor { MAIN_OUTPUT }`, executed over the command socket. Reusing the
  planner's guard is what keeps "never focus an already-focused workspace" and
  the three-branch focus rule (ARCHITECTURE.md, gotcha §9.5) identical to every
  other command.

### Global-lock suppression handshake

Bash's `global_lock_is_busy` (`bin/niri-ctx:1212-1223`) probes the same flock a
mutating command takes, so the watcher stays out of the way during scripted
focus sequences. Rust port:

- Path is the shared bridge lock `${XDG_RUNTIME_DIR:-cache}/niri-ctx.lock`
  (ARCHITECTURE.md "Locking & bridge compatibility"). Open it, `flock` **LOCK_NB**:
  if it locks, immediately unlock+close and treat as *free*; if it fails with
  `EWOULDBLOCK`, treat as *busy* and skip this event. The probe fd MUST be
  `O_CLOEXEC` (never inherited — same reason as review finding #4).
- `ignore_until` is the *self*-suppression half (the watcher ignoring its own
  focus actions); the lock probe is the *other-command* half (ignoring focus
  churn a concurrent `niri-ctx open` is actively causing). Both are required.
- The 700ms value matches Bash's `WATCH_IGNORE_UNTIL=now+700`; unlike Bash it is
  a private `Instant` on the main thread, not a global epoch-millis variable.

## 4. Debounce

Focus events arrive in bursts (alt-tabbing sweeps focus across several windows;
a workspace switch fires `WindowFocusChanged` + a folded `WindowOpenedOrChanged`).
Bash has no debounce — it relies solely on the 700ms post-action suppression and
the guarded no-op. That is *correct but chatty*: it may issue a TOP focus for an
intermediate window the user tabbed through in passing.

Design: **trailing-edge debounce, N = 150 ms**, on the focus *consideration*
(not on cache updates — caches always apply immediately). Implementation with no
timers: keep `pending: Option<WindowId>` and `pending_since: Instant`. On a
focus-bearing message, set `pending` and continue. Block on
`recv_timeout(150ms - elapsed)`; when it times out with a `pending` still set,
run `consider_focus(pending)` and clear it. A newer focus event within the
window overwrites `pending` (coalesce to the latest).

Why 150 ms and why adding one is safe: top-follow's action is a *pure function of
the currently focused window* and is idempotent under the guard (settled state →
empty plan). Coalescing therefore only ever drops redundant intermediate
targets; it can never produce a different final state than the last focus event.
150 ms is below human "did that lag?" perception yet long enough to swallow a
tab-sweep. Cache folds are never debounced, so `wait_for_window`-style
correctness (a different code path) is unaffected. Keep N in config only if it
proves annoying; do not build config hot-reload for it.

## 5. Reconnect / niri restart

On `WatchMsg::Disconnected` (EOF or read error):

1. **Drop all caches** (window ids from the old compositor instance are invalid —
   NIRI_IPC_NOTES §5/§7; a stale cache would mis-target top-follow).
2. Clear `ignore_until` and `pending`.
3. A niri restart changes `$NIRI_SOCKET` (the path embeds the compositor PID),
   **and a long-running process's own `environ` is frozen** — an in-process
   reconnect literally cannot learn the new socket path. So:
   - Do a **bounded quick retry** at the current socket (a few attempts,
     backoff **1s → 30s** exponential, capped) to ride out a momentary blip
     where the path is unchanged. This preserves the Bash reconnect loop shape
     (`bin/niri-ctx:1325-1327`).
   - If quick retries exhaust, **exit non-zero** and let systemd
     (`Restart=on-failure`, `RestartSec=2`) respawn the process with a *fresh*
     `graphical-session.target` environment carrying the new `NIRI_SOCKET`.
     **Recommended primary path.** Rationale: exiting is the only way to obtain a
     valid post-restart socket; a self-managed reconnect that re-reads `env`
     would just re-read the stale value and spin. For a manual/headless run (unit
     disabled) the process simply exits and the user re-runs — acceptable because
     the watcher is optional.
4. After any successful (re)connect, **wait for the first `WorkspacesChanged` and
   `WindowsChanged`** (niri sends both as the opening snapshot on a fresh
   `EventStream`) before honoring any focus event — never act on partial caches.
   Track two `bool`s; gate `consider_focus` on both being set.

## 6. systemd user unit

Reuse the existing shape unchanged (`.config/systemd/user/niri-ctx-watch.service`,
audit §9):

```ini
[Unit]
Description=niri context workspace watcher
After=graphical-session.target
PartOf=graphical-session.target
[Service]
Type=simple
ExecStart=%h/.local/bin/niri-ctx watch
Restart=on-failure
RestartSec=2
[Install]
WantedBy=graphical-session.target
```

- **`install.sh` MUST NOT enable or link it.** Keep the current behavior
  (`install.sh:62-68`): report if already active, otherwise leave it alone.
- Enable (opt-in, by the user only):
  `systemctl --user enable --now niri-ctx-watch.service`
  and set `top_follow = "devtools"` (or `ambient`) in config.
- Disable: `systemctl --user disable --now niri-ctx-watch.service`.
- `doctor` reports `systemctl --user is-active niri-ctx-watch` (already ported).
- `Restart=on-failure` is what makes the "exit on restart" strategy in §5 work;
  the quiet `exit 0` preflight (no socket) is deliberately *not* a failure, so a
  no-niri boot won't thrash-restart.

## 7. Guarded focus in the watcher

The watcher performs exactly one kind of niri mutation: switching `TOP_OUTPUT`'s
workspace (plus the trailing `focus-monitor MAIN`). It MUST use the planner's
`focus_workspace_guarded(&state, TOP_OUTPUT, target)` against a fresh snapshot —
the same function every other command uses — so all three branches hold:
early-return if the target workspace is already `is_focused`; `focus-monitor`
only if `TOP_OUTPUT` isn't already focused; `focus-workspace` only if the target
isn't already active on `TOP_OUTPUT`. This is the guard against
`workspace-auto-back-and-forth` (NIRI_IPC_NOTES §5 gotcha #1). No naked
`focus-workspace` anywhere in the watcher.

## 8. Failure & observability

Log to the shared file (`~/.cache/niri-ctx/log`) plus stderr under `--verbose`,
via the existing `tracing` setup:

- **INFO**, one line per acted top-follow: `top-follow: <ctx> focus=<window>
  app=<app_id> → TOP=<target>`. This is the "why did the watcher do that" record.
- **INFO** on connect/disconnect/reconnect with reason and backoff.
- **DEBUG**: skipped events with the reason (lock busy, ignore window, wrong
  output, Admin, no target) — enough to explain a *non*-action, off by default.
- **TRACE**: dropped unknown event tags.
- **Rate-limit the noisy paths.** `consider_focus` can be called on every focus
  change; log skips at DEBUG only and collapse repeats (e.g. suppress identical
  consecutive "lock busy" / "ignore window" lines). Acted top-follows are rare
  (gated by the target `!=` current check) so INFO for those is not spammy.

Diagnosing "the watcher did something surprising": `tail` the log; each action
line carries the focused window id, its app-id, the derived context, and the
resolved TOP target — enough to reconstruct the decision. `niri-ctx inspect`
dumps the live `DesktopState` to compare against what the caches believed.

## 9. Implementation checklist (ordered, small)

1. `WatchMsg` enum + `decode_line(&str) -> Option<WatchMsg>` (lenient tag-peek;
   lift/share the tag+payload logic from `ipc.rs:windows_from_event_line`).
   Unit-test with recorded event lines incl. an unknown tag and a malformed line.
2. Reader thread: subscribe `EventStream` on a dedicated socket (reuse the
   ack-handling in `ipc.rs:event_stream`), loop `read_line` → `decode_line` →
   `send`; `Disconnected` on EOF/error.
3. `Caches` + fold rules; unit-test each `WatchMsg` against a cache fixture.
4. `consider_focus` as a **pure** decision fn `(caches, cfg, id) ->
   Option<TopTarget>` — unit-test the whole §3 truth table (devtools/ambient/off,
   helium/non-helium, Admin, wrong output, unknown ctx). Keep it pure so it needs
   no live niri.
5. `apply_top_follow`: fresh snapshot → early `==` check → set `ignore_until` →
   `focus_workspace_guarded` + `FocusMonitor` over the command socket. (Needs the
   Phase-3 executor/command path; watcher lands after mutation is enabled.)
6. Global-lock probe helper (`O_CLOEXEC`, `flock` `LOCK_NB`, unlock+close).
7. Main loop: `recv_timeout` debounce (§4) + snapshot-gating (§5 step 4) +
   reconnect/exit (§5).
8. Wire `commands/watch.rs::run()` (currently `NotImplementedUseBash`) to the
   preflight + loop. Keep the quiet `exit 0` preflight.
9. Leave the systemd unit and `install.sh` exactly as-is; add enable/disable docs
   to WORKFLOW.md only.

## 10. Risks

- **Frozen `environ` vs new `NIRI_SOCKET`** (§5): the exit-and-let-systemd path
  is load-bearing; if someone "fixes" it into an in-process env re-read it will
  silently fail to reconnect after a niri restart. Comment it loudly.
- **Self-trigger loop**: forgetting to set `ignore_until` *before* issuing focus
  re-enters `consider_focus` on the watcher's own event → focus thrash. The
  700ms window + the guarded no-op both defend this; keep both.
- **Cache/live divergence**: acting on event caches alone could target a stale
  workspace; §3 mandates a fresh snapshot for the actual focus, so caches only
  ever choose a *target name*, never issue focus from stale ids.
- **Accidental enable**: removing `top_follow = off` from config re-arms behavior
  if the unit is ever enabled (audit §11). `doctor` should surface both
  `is-active` and the effective `top_follow` so the two can't silently disagree.
- **Debounce masking a real switch**: only if N were large; 150 ms with
  coalesce-to-latest cannot drop the final target, so the risk is cosmetic
  latency, not wrong state.
