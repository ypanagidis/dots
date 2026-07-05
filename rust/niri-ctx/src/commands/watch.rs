use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use crate::config::Config;
use crate::error::{NiriCtxError, Result};
use crate::lock::GlobalLock;
use crate::model::{Context, WindowId, WorkspaceId};
use crate::niri::ipc::{watch_event_from_line, IpcNiriClient, WatchEvent};
use crate::niri::{NiriAction, NiriClient, Window, Workspace};
use crate::planner::{focus_workspace_guarded, Effect};
use crate::state::DesktopState;

const DEBOUNCE: Duration = Duration::from_millis(150);
const SELF_SUPPRESS: Duration = Duration::from_millis(700);
const RECONNECT_BACKOFFS: [Duration; 6] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(4),
    Duration::from_secs(8),
    Duration::from_secs(16),
    Duration::from_secs(30),
];
const REPEATED_LOG_WINDOW: Duration = Duration::from_secs(5);

#[derive(Debug)]
enum WatchMsg {
    Workspaces(Vec<Workspace>),
    Windows(Vec<Window>),
    WindowOpenedOrChanged(Window),
    WindowClosed(WindowId),
    WindowFocus(Option<WindowId>),
    Disconnected(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct WinInfo {
    app_id: String,
    ws_id: WorkspaceId,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct WsInfo {
    name: String,
    output: String,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct Caches {
    win: HashMap<WindowId, WinInfo>,
    ws: HashMap<WorkspaceId, WsInfo>,
}

impl Caches {
    fn apply(&mut self, msg: WatchMsg) -> Option<WindowId> {
        match msg {
            WatchMsg::Workspaces(workspaces) => {
                self.ws = workspaces
                    .into_iter()
                    .map(|workspace| {
                        (
                            workspace.id,
                            WsInfo {
                                name: workspace.name.unwrap_or_default(),
                                output: workspace.output,
                            },
                        )
                    })
                    .collect();
                None
            }
            WatchMsg::Windows(windows) => {
                self.win = windows
                    .into_iter()
                    .map(|window| {
                        (
                            window.id,
                            WinInfo {
                                app_id: window.app_id,
                                ws_id: window.workspace_id,
                            },
                        )
                    })
                    .collect();
                None
            }
            WatchMsg::WindowOpenedOrChanged(window) => {
                let id = window.id;
                let is_focused = window.is_focused;
                self.win.insert(
                    id,
                    WinInfo {
                        app_id: window.app_id,
                        ws_id: window.workspace_id,
                    },
                );
                is_focused.then_some(id)
            }
            WatchMsg::WindowClosed(id) => {
                self.win.remove(&id);
                None
            }
            WatchMsg::WindowFocus(id) => id,
            WatchMsg::Disconnected(_) => None,
        }
    }

    fn clear(&mut self) {
        self.win.clear();
        self.ws.clear();
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TopFollowMode {
    Off,
    Devtools,
    Ambient,
}

impl TopFollowMode {
    fn parse(value: &str) -> Self {
        match value {
            "ambient" => Self::Ambient,
            "off" => Self::Off,
            _ => Self::Devtools,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct TopFollowAction {
    ctx: Context,
    focus: WindowId,
    app_id: String,
    target: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum TopFollowDecision {
    Apply(TopFollowAction),
    Skip(&'static str),
}

#[derive(Debug, Default)]
struct RateLimitedLogs {
    last: HashMap<String, Instant>,
}

impl RateLimitedLogs {
    fn debug(&mut self, line: impl Into<String>) {
        let line = line.into();
        let now = Instant::now();
        if self
            .last
            .get(&line)
            .is_some_and(|last| now.duration_since(*last) < REPEATED_LOG_WINDOW)
        {
            return;
        }
        self.last.insert(line.clone(), now);
        tracing::debug!("{line}");
    }
}

#[derive(Debug)]
struct WatchSessionEnd {
    reason: String,
    saw_message: bool,
}

pub fn run(cfg: &Config) -> Result<()> {
    let mode = TopFollowMode::parse(&cfg.behavior.top_follow);
    if mode == TopFollowMode::Off {
        // Bash idles with top-follow disabled. Rust exits successfully so the
        // opt-in systemd unit with Restart=on-failure stays quiet.
        tracing::info!("watch exit: TOP_FOLLOW=off");
        return Ok(());
    }

    let Some(socket) = std::env::var_os("NIRI_SOCKET").map(PathBuf::from) else {
        tracing::info!("watch exit: NIRI_SOCKET unset");
        return Ok(());
    };

    let mut client = IpcNiriClient::new();
    if let Err(err) = client.workspaces() {
        tracing::info!("watch exit: niri socket unreachable: {err}");
        return Ok(());
    }

    let mut attempt = 0;
    let mut ignore_until: Option<Instant> = None;
    loop {
        tracing::info!(socket = %socket.display(), "watch event-stream connecting");
        let end = run_one_session(cfg, mode, &socket, &mut client, &mut ignore_until);
        let end = match end {
            Ok(end) => end,
            Err(err) => WatchSessionEnd {
                reason: err.to_string(),
                saw_message: false,
            },
        };
        tracing::info!(reason = %end.reason, "watch event-stream disconnected");
        ignore_until = None;
        if end.saw_message {
            attempt = 0;
        }
        let Some(backoff) = RECONNECT_BACKOFFS.get(attempt).copied() else {
            return Err(NiriCtxError::Ipc(
                "watch event-stream reconnect retries exhausted".to_string(),
            ));
        };
        attempt += 1;
        tracing::info!(
            reason = %end.reason,
            backoff_secs = backoff.as_secs(),
            "watch event-stream reconnecting"
        );
        thread::sleep(backoff);
    }
}

fn run_one_session(
    cfg: &Config,
    mode: TopFollowMode,
    socket: &Path,
    client: &mut IpcNiriClient,
    ignore_until: &mut Option<Instant>,
) -> Result<WatchSessionEnd> {
    let (tx, rx) = mpsc::channel();
    spawn_reader(socket.to_path_buf(), tx);

    let mut caches = Caches::default();
    let mut have_workspaces = false;
    let mut have_windows = false;
    let mut pending: Option<(WindowId, Instant)> = None;
    let mut logs = RateLimitedLogs::default();
    let mut saw_message = false;

    loop {
        let received = if let Some((_, since)) = pending {
            let timeout = DEBOUNCE.saturating_sub(since.elapsed());
            rx.recv_timeout(timeout)
        } else {
            match rx.recv() {
                Ok(msg) => Ok(msg),
                Err(_) => {
                    return Ok(WatchSessionEnd {
                        reason: "event reader channel closed".to_string(),
                        saw_message,
                    });
                }
            }
        };

        match received {
            Ok(msg) => {
                if let WatchMsg::Disconnected(reason) = msg {
                    caches.clear();
                    *ignore_until = None;
                    return Ok(WatchSessionEnd {
                        reason,
                        saw_message,
                    });
                }
                saw_message = true;

                match &msg {
                    WatchMsg::Workspaces(_) => have_workspaces = true,
                    WatchMsg::Windows(_) => have_windows = true,
                    _ => {}
                }
                if let Some(id) = caches.apply(msg) {
                    pending = Some((id, Instant::now()));
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                let Some((id, _)) = pending.take() else {
                    continue;
                };
                if !(have_workspaces && have_windows) {
                    logs.debug("watch skip: waiting for initial workspace/window snapshots");
                    continue;
                }
                consider_focus(cfg, mode, &caches, id, client, ignore_until, &mut logs)?;
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                return Ok(WatchSessionEnd {
                    reason: "event reader channel closed".to_string(),
                    saw_message,
                });
            }
        }
    }
}

fn spawn_reader(socket: PathBuf, sender: mpsc::Sender<WatchMsg>) {
    thread::spawn(move || {
        let reason = match read_events(&socket, &sender) {
            Ok(()) => "EOF".to_string(),
            Err(err) => err.to_string(),
        };
        let _ = sender.send(WatchMsg::Disconnected(reason));
    });
}

fn read_events(socket: &Path, sender: &mpsc::Sender<WatchMsg>) -> Result<()> {
    let mut stream = UnixStream::connect(socket).map_err(|err| NiriCtxError::io(socket, err))?;
    let mut request = serde_json::to_string(&niri_ipc::Request::EventStream)?;
    request.push('\n');
    stream
        .write_all(request.as_bytes())
        .map_err(|err| NiriCtxError::Ipc(format!("subscribe event stream: {err}")))?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    let bytes = reader
        .read_line(&mut line)
        .map_err(|err| NiriCtxError::Ipc(format!("read event-stream ack: {err}")))?;
    if bytes == 0 {
        return Err(NiriCtxError::Ipc(
            "event-stream ack reached EOF".to_string(),
        ));
    }
    match serde_json::from_str::<niri_ipc::Reply>(&line)? {
        Ok(niri_ipc::Response::Handled) => {}
        Ok(response) => {
            return Err(NiriCtxError::Ipc(format!(
                "unexpected event-stream response: {response:?}"
            )));
        }
        Err(err) => return Err(NiriCtxError::Ipc(err)),
    }

    tracing::info!(socket = %socket.display(), "watch event-stream connected");
    line.clear();
    loop {
        let bytes = reader
            .read_line(&mut line)
            .map_err(|err| NiriCtxError::Ipc(format!("read event: {err}")))?;
        if bytes == 0 {
            return Ok(());
        }
        if let Some(event) = watch_event_from_line(&line) {
            let msg = match event {
                WatchEvent::WorkspacesChanged(workspaces) => WatchMsg::Workspaces(workspaces),
                WatchEvent::WindowsChanged(windows) => WatchMsg::Windows(windows),
                WatchEvent::WindowOpenedOrChanged(window) => {
                    WatchMsg::WindowOpenedOrChanged(window)
                }
                WatchEvent::WindowClosed(id) => WatchMsg::WindowClosed(id),
                WatchEvent::WindowFocusChanged(id) => WatchMsg::WindowFocus(id),
            };
            if sender.send(msg).is_err() {
                return Ok(());
            }
        }
        line.clear();
    }
}

fn consider_focus(
    cfg: &Config,
    mode: TopFollowMode,
    caches: &Caches,
    focused_id: WindowId,
    client: &mut IpcNiriClient,
    ignore_until: &mut Option<Instant>,
    logs: &mut RateLimitedLogs,
) -> Result<()> {
    let ignore_active = ignore_until.is_some_and(|deadline| Instant::now() < deadline);
    let lock_busy = if ignore_active {
        false
    } else {
        GlobalLock::is_busy_probe()?
    };
    let decision = decide_top_follow(
        mode,
        &cfg.outputs.main,
        ignore_active,
        lock_busy,
        caches,
        focused_id,
    );
    let action = match decision {
        TopFollowDecision::Apply(action) => action,
        TopFollowDecision::Skip(reason) => {
            logs.debug(format!("watch skip: {reason}"));
            return Ok(());
        }
    };
    apply_top_follow(cfg, client, ignore_until, &action)
}

fn decide_top_follow(
    mode: TopFollowMode,
    main_output: &str,
    ignore_active: bool,
    lock_busy: bool,
    caches: &Caches,
    focused_id: WindowId,
) -> TopFollowDecision {
    if mode == TopFollowMode::Off {
        return TopFollowDecision::Skip("top_follow off");
    }
    if ignore_active {
        return TopFollowDecision::Skip("self suppression active");
    }
    if lock_busy {
        return TopFollowDecision::Skip("global lock busy");
    }

    let Some(win) = caches.win.get(&focused_id) else {
        return TopFollowDecision::Skip("focused window missing from cache");
    };
    let Some(ws) = caches.ws.get(&win.ws_id) else {
        return TopFollowDecision::Skip("focused workspace missing from cache");
    };
    if ws.output != main_output {
        return TopFollowDecision::Skip("focused workspace is not on main output");
    }
    let Some(ctx) = Context::from_workspace_name(&ws.name) else {
        return TopFollowDecision::Skip("focused workspace is not a context");
    };
    if ctx == Context::Admin {
        return TopFollowDecision::Skip("Admin has no devtools workspace");
    }

    let target = match mode {
        TopFollowMode::Devtools if win.app_id == "helium" => format!("{}-devtools", ctx.name()),
        TopFollowMode::Ambient if win.app_id != "helium" => "top-ambient".to_string(),
        TopFollowMode::Off | TopFollowMode::Devtools | TopFollowMode::Ambient => {
            return TopFollowDecision::Skip("no top-follow target for focused app");
        }
    };

    TopFollowDecision::Apply(TopFollowAction {
        ctx,
        focus: focused_id,
        app_id: win.app_id.clone(),
        target,
    })
}

fn apply_top_follow(
    cfg: &Config,
    client: &mut IpcNiriClient,
    ignore_until: &mut Option<Instant>,
    action: &TopFollowAction,
) -> Result<()> {
    let state = DesktopState::snapshot(client)?;
    if state.active_workspace_name_on_output(&cfg.outputs.top) == Some(action.target.as_str()) {
        return Ok(());
    }

    let effects = top_follow_effects(cfg, &state, &action.target);
    if effects.is_empty() {
        return Ok(());
    }

    *ignore_until = Some(Instant::now() + SELF_SUPPRESS);
    tracing::info!(
        ctx = %action.ctx,
        focus = action.focus.0,
        app = %action.app_id,
        target = %action.target,
        "top-follow"
    );
    for effect in effects {
        match effect {
            Effect::FocusOutput { output } => client.action(NiriAction::FocusOutput { output })?,
            Effect::FocusWorkspace { ws, .. } => {
                client.action(NiriAction::FocusWorkspace { reference: ws })?
            }
            Effect::Fail { diag } => {
                tracing::debug!("top-follow skipped: {diag}");
                return Ok(());
            }
            _ => {}
        }
    }
    Ok(())
}

fn top_follow_effects(cfg: &Config, state: &DesktopState, target: &str) -> Vec<Effect> {
    let mut effects = focus_workspace_guarded(state, &cfg.outputs.top, target);
    if effects
        .iter()
        .any(|effect| matches!(effect, Effect::Fail { .. }))
    {
        return effects;
    }
    effects.push(Effect::FocusOutput {
        output: cfg.outputs.main.clone(),
    });
    effects
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::WorkspaceRef;

    fn ws(id: u64, name: &str, output: &str, active: bool, focused: bool) -> Workspace {
        Workspace {
            id: WorkspaceId(id),
            name: Some(name.to_string()),
            output: output.to_string(),
            is_active: active,
            is_focused: focused,
        }
    }

    fn win(id: u64, app_id: &str, ws_id: u64, focused: bool) -> Window {
        Window {
            id: WindowId(id),
            title: String::new(),
            app_id: app_id.to_string(),
            pid: 0,
            workspace_id: WorkspaceId(ws_id),
            is_focused: focused,
            is_floating: false,
            column: None,
            tile_height: Some(500.0),
        }
    }

    fn caches() -> Caches {
        let mut caches = Caches::default();
        caches.apply(WatchMsg::Workspaces(vec![
            ws(1, "UP", "DP-1", true, true),
            ws(2, "UP-devtools", "DP-2", true, false),
            ws(3, "Admin", "DP-1", false, false),
            ws(4, "Side", "HDMI-A-1", true, false),
        ]));
        caches.apply(WatchMsg::Windows(vec![
            win(10, "helium", 1, true),
            win(11, "ghostty", 1, false),
            win(12, "helium", 3, false),
            win(13, "ghostty", 4, false),
        ]));
        caches
    }

    #[test]
    fn cache_fold_replaces_upserts_closes_and_reports_focus() {
        let mut caches = Caches::default();
        caches.apply(WatchMsg::Workspaces(vec![ws(1, "UP", "DP-1", true, true)]));
        caches.apply(WatchMsg::Windows(vec![win(10, "helium", 1, false)]));
        assert_eq!(caches.ws.len(), 1);
        assert_eq!(caches.win.len(), 1);

        caches.apply(WatchMsg::Workspaces(vec![ws(
            2, "Side", "DP-1", true, true,
        )]));
        assert!(!caches.ws.contains_key(&WorkspaceId(1)));
        assert_eq!(caches.ws[&WorkspaceId(2)].name, "Side");

        assert_eq!(
            caches.apply(WatchMsg::WindowOpenedOrChanged(win(20, "ghostty", 2, true))),
            Some(WindowId(20))
        );
        assert_eq!(caches.win[&WindowId(20)].app_id, "ghostty");
        assert_eq!(
            caches.apply(WatchMsg::WindowFocus(Some(WindowId(10)))),
            Some(WindowId(10))
        );
        caches.apply(WatchMsg::WindowClosed(WindowId(20)));
        assert!(!caches.win.contains_key(&WindowId(20)));
    }

    #[test]
    fn top_follow_decision_table() {
        let caches = caches();

        assert_eq!(
            decide_top_follow(
                TopFollowMode::Off,
                "DP-1",
                false,
                false,
                &caches,
                WindowId(10)
            ),
            TopFollowDecision::Skip("top_follow off")
        );
        assert_eq!(
            decide_top_follow(
                TopFollowMode::Devtools,
                "DP-1",
                false,
                false,
                &caches,
                WindowId(10)
            ),
            TopFollowDecision::Apply(TopFollowAction {
                ctx: Context::UP,
                focus: WindowId(10),
                app_id: "helium".to_string(),
                target: "UP-devtools".to_string(),
            })
        );
        assert_eq!(
            decide_top_follow(
                TopFollowMode::Ambient,
                "DP-1",
                false,
                false,
                &caches,
                WindowId(11)
            ),
            TopFollowDecision::Apply(TopFollowAction {
                ctx: Context::UP,
                focus: WindowId(11),
                app_id: "ghostty".to_string(),
                target: "top-ambient".to_string(),
            })
        );
        assert_eq!(
            decide_top_follow(
                TopFollowMode::Devtools,
                "DP-1",
                false,
                false,
                &caches,
                WindowId(12)
            ),
            TopFollowDecision::Skip("Admin has no devtools workspace")
        );
        assert_eq!(
            decide_top_follow(
                TopFollowMode::Ambient,
                "DP-1",
                false,
                false,
                &caches,
                WindowId(13)
            ),
            TopFollowDecision::Skip("focused workspace is not on main output")
        );
        assert_eq!(
            decide_top_follow(
                TopFollowMode::Devtools,
                "DP-1",
                true,
                false,
                &caches,
                WindowId(10)
            ),
            TopFollowDecision::Skip("self suppression active")
        );
    }

    #[test]
    fn top_follow_effects_use_guarded_top_focus_then_main_monitor() {
        let cfg = Config::default_for_repo("/tmp/repo");
        let state = DesktopState::new(
            vec![
                ws(1, "UP", "DP-1", true, true),
                ws(2, "UP-devtools", "DP-2", false, false),
                ws(3, "top-ambient", "DP-2", true, false),
            ],
            vec![],
        );
        assert_eq!(
            top_follow_effects(&cfg, &state, "UP-devtools"),
            vec![
                Effect::FocusOutput {
                    output: "DP-2".to_string()
                },
                Effect::FocusWorkspace {
                    output: "DP-2".to_string(),
                    ws: WorkspaceRef::name("UP-devtools"),
                },
                Effect::FocusOutput {
                    output: "DP-1".to_string()
                },
            ]
        );
    }
}
