use std::collections::BTreeSet;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use serde::Deserialize;

use crate::error::{NiriCtxError, Result};
use crate::model::{WindowId, WindowMatcher, WorkspaceId};

use super::{NiriAction, NiriClient, Window, Workspace};

#[derive(Debug, Default)]
pub struct IpcNiriClient;

impl IpcNiriClient {
    pub fn new() -> Self {
        Self
    }

    pub fn version(&mut self) -> Result<String> {
        match request(niri_ipc::Request::Version)? {
            niri_ipc::Response::Version(version) => Ok(version),
            response => Err(NiriCtxError::Ipc(format!(
                "unexpected Version response: {response:?}"
            ))),
        }
    }
}

impl NiriClient for IpcNiriClient {
    fn workspaces(&mut self) -> Result<Vec<Workspace>> {
        match request(niri_ipc::Request::Workspaces)? {
            niri_ipc::Response::Workspaces(workspaces) => {
                Ok(workspaces.into_iter().map(Workspace::from).collect())
            }
            response => Err(NiriCtxError::Ipc(format!(
                "unexpected Workspaces response: {response:?}"
            ))),
        }
    }

    fn windows(&mut self) -> Result<Vec<Window>> {
        match request(niri_ipc::Request::Windows)? {
            niri_ipc::Response::Windows(windows) => {
                Ok(windows.into_iter().map(Window::from).collect())
            }
            response => Err(NiriCtxError::Ipc(format!(
                "unexpected Windows response: {response:?}"
            ))),
        }
    }

    fn action(&mut self, _action: NiriAction) -> Result<()> {
        Err(NiriCtxError::ReadOnlyEffect(Box::new(
            crate::planner::Effect::Log {
                level: "error".to_string(),
                msg: "direct IPC actions are disabled in Phase 1".to_string(),
            },
        )))
    }

    fn wait_for_window(
        &mut self,
        matcher: &WindowMatcher,
        timeout: Duration,
    ) -> Result<Option<Window>> {
        let deadline = Instant::now() + timeout;
        let (sender, receiver) = mpsc::channel();
        let matcher_for_thread = matcher.clone();
        let socket_path = std::env::var_os("NIRI_SOCKET").map(std::path::PathBuf::from);

        if let Some(path) = socket_path {
            thread::spawn(move || {
                let result = event_stream(path, matcher_for_thread, sender, deadline);
                if let Err(err) = result {
                    tracing::debug!("event stream wait ended: {err}");
                }
            });
        }

        if let Some(window) = find_matching(&self.windows()?, matcher) {
            return Ok(Some(window));
        }

        while Instant::now() < deadline {
            let remaining = deadline.saturating_duration_since(Instant::now());
            let wait = remaining.min(Duration::from_millis(500));
            match receiver.recv_timeout(wait) {
                Ok(window) => return Ok(Some(window)),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if let Some(window) = find_matching(&self.windows()?, matcher) {
                        return Ok(Some(window));
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    // Event thread is gone (stream failed or NIRI_SOCKET unset);
                    // recv would return instantly forever, so pace the polling
                    // ourselves instead of busy-looping on the command socket.
                    if let Some(window) = find_matching(&self.windows()?, matcher) {
                        return Ok(Some(window));
                    }
                    thread::sleep(wait);
                }
            }
        }
        Ok(None)
    }
}

fn request(request: niri_ipc::Request) -> Result<niri_ipc::Response> {
    let name = format!("{request:?}");
    let mut socket = niri_ipc::socket::Socket::connect()
        .map_err(|err| NiriCtxError::Ipc(format!("connect to niri socket: {err}")))?;
    match socket
        .send(request)
        .map_err(|err| NiriCtxError::Ipc(format!("send {name}: {err}")))?
    {
        Ok(response) => Ok(response),
        Err(err) => Err(NiriCtxError::Ipc(err)),
    }
}

#[allow(dead_code)]
fn event_stream(
    path: std::path::PathBuf,
    matcher: WindowMatcher,
    sender: mpsc::Sender<Window>,
    deadline: Instant,
) -> Result<()> {
    let mut stream = UnixStream::connect(&path).map_err(|err| NiriCtxError::io(path, err))?;
    stream
        .set_read_timeout(Some(Duration::from_millis(500)))
        .map_err(|err| NiriCtxError::Ipc(format!("configure event stream timeout: {err}")))?;
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
    line.clear();
    while Instant::now() < deadline {
        let bytes = match reader.read_line(&mut line) {
            Ok(bytes) => bytes,
            Err(err)
                if matches!(
                    err.kind(),
                    std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                ) =>
            {
                continue;
            }
            Err(err) => return Err(NiriCtxError::Ipc(format!("read event: {err}"))),
        };
        if bytes == 0 {
            break;
        }
        for window in windows_from_event_line(&line) {
            if matches_window(&window, &matcher) && sender.send(window).is_err() {
                return Ok(());
            }
        }
        line.clear();
    }
    Ok(())
}

#[allow(dead_code)]
fn windows_from_event_line(line: &str) -> Vec<Window> {
    let value: serde_json::Value = match serde_json::from_str(line) {
        Ok(value) => value,
        Err(err) => {
            tracing::debug!("skipping malformed event: {err}");
            return Vec::new();
        }
    };
    let Some(object) = value.as_object() else {
        return Vec::new();
    };
    let Some((tag, payload)) = object.iter().next() else {
        return Vec::new();
    };
    match tag.as_str() {
        "WindowsChanged" => {
            #[derive(Deserialize)]
            struct Payload {
                windows: Vec<niri_ipc::Window>,
            }
            match serde_json::from_value::<Payload>(payload.clone()) {
                Ok(payload) => payload.windows.into_iter().map(Window::from).collect(),
                Err(err) => {
                    tracing::debug!("skipping malformed WindowsChanged event: {err}");
                    Vec::new()
                }
            }
        }
        "WindowOpenedOrChanged" => {
            #[derive(Deserialize)]
            struct Payload {
                window: niri_ipc::Window,
            }
            match serde_json::from_value::<Payload>(payload.clone()) {
                Ok(payload) => vec![Window::from(payload.window)],
                Err(err) => {
                    tracing::debug!("skipping malformed WindowOpenedOrChanged event: {err}");
                    Vec::new()
                }
            }
        }
        _ => {
            tracing::debug!("skipping unknown niri event {tag}");
            Vec::new()
        }
    }
}

#[allow(dead_code)]
fn find_matching(windows: &[Window], matcher: &WindowMatcher) -> Option<Window> {
    let mut matches = windows
        .iter()
        .filter(|window| matches_window(window, matcher))
        .cloned()
        .collect::<Vec<_>>();
    matches.sort_by_key(|window| window.id);
    matches.into_iter().next()
}

#[allow(dead_code)]
fn matches_window(window: &Window, matcher: &WindowMatcher) -> bool {
    match matcher {
        WindowMatcher::AppIdExact(app_id) => &window.app_id == app_id,
        WindowMatcher::NewAppIdExcluding { app_id, before } => {
            &window.app_id == app_id && !before.contains(&window.id)
        }
        WindowMatcher::CachedId { id, expect_app_id } => {
            window.id == *id && &window.app_id == expect_app_id
        }
    }
}

impl From<niri_ipc::Workspace> for Workspace {
    fn from(raw: niri_ipc::Workspace) -> Self {
        Self {
            id: WorkspaceId(raw.id),
            name: raw.name,
            output: raw.output.unwrap_or_default(),
            is_active: raw.is_active,
            is_focused: raw.is_focused,
        }
    }
}

impl From<niri_ipc::Window> for Window {
    fn from(raw: niri_ipc::Window) -> Self {
        Self {
            id: WindowId(raw.id),
            title: raw.title.unwrap_or_default(),
            app_id: raw.app_id.unwrap_or_default(),
            pid: raw
                .pid
                .and_then(|pid| u32::try_from(pid).ok())
                .unwrap_or_default(),
            workspace_id: WorkspaceId(raw.workspace_id.unwrap_or_default()),
            is_focused: raw.is_focused,
            is_floating: raw.is_floating,
            column: raw.layout.pos_in_scrolling_layout,
        }
    }
}

#[allow(dead_code)]
fn ids_for_app(windows: &[Window], app_id: &str) -> BTreeSet<WindowId> {
    windows
        .iter()
        .filter(|window| window.app_id == app_id)
        .map(|window| window.id)
        .collect()
}
