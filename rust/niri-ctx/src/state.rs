use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::io::ErrorKind;
use std::path::PathBuf;

use crate::config::Config;
use crate::error::{NiriCtxError, Result};
use crate::model::{BrowserRole, Context, OutputName, WindowId, WorkspaceId};
use crate::niri::{NiriClient, Window, Workspace};

#[derive(Debug, Clone, serde::Serialize)]
pub struct DesktopState {
    pub workspaces: Vec<Workspace>,
    pub windows: Vec<Window>,
    pub focused_window: Option<WindowId>,
    pub focused_workspace: Option<WorkspaceId>,
    pub active_ws_by_output: HashMap<OutputName, WorkspaceId>,
    #[serde(skip)]
    browser_cache: HashMap<(String, BrowserRole), WindowId>,
    #[serde(skip)]
    by_workspace_name: HashMap<String, WorkspaceId>,
    #[serde(skip)]
    by_workspace_id: HashMap<WorkspaceId, Workspace>,
    #[serde(skip)]
    by_window_id: HashMap<WindowId, Window>,
}

impl DesktopState {
    pub fn new(workspaces: Vec<Workspace>, windows: Vec<Window>) -> Self {
        let focused_window = windows
            .iter()
            .find(|window| window.is_focused)
            .map(|window| window.id);
        let focused_workspace = workspaces
            .iter()
            .find(|workspace| workspace.is_focused)
            .map(|workspace| workspace.id);
        let active_ws_by_output = workspaces
            .iter()
            .filter(|workspace| workspace.is_active)
            .map(|workspace| (workspace.output.clone(), workspace.id))
            .collect();
        let by_workspace_name = workspaces
            .iter()
            .filter_map(|workspace| {
                workspace
                    .name
                    .as_ref()
                    .map(|name| (name.to_ascii_lowercase(), workspace.id))
            })
            .collect();
        let by_workspace_id = workspaces
            .iter()
            .cloned()
            .map(|workspace| (workspace.id, workspace))
            .collect();
        let by_window_id = windows
            .iter()
            .cloned()
            .map(|window| (window.id, window))
            .collect();

        Self {
            workspaces,
            windows,
            focused_window,
            focused_workspace,
            active_ws_by_output,
            browser_cache: HashMap::new(),
            by_workspace_name,
            by_workspace_id,
            by_window_id,
        }
    }

    pub fn snapshot(client: &mut dyn NiriClient) -> Result<Self> {
        let workspaces = client.workspaces()?;
        let windows = client.windows()?;
        Ok(Self::new(workspaces, windows))
    }

    pub fn load_browser_cache(&mut self, cfg: &Config) -> Result<()> {
        self.browser_cache.clear();
        for context in &cfg.contexts {
            self.load_browser_cache_entry(&context.slug, BrowserRole::Docs)?;
            self.load_browser_cache_entry(&context.slug, BrowserRole::Output)?;
        }
        self.load_browser_cache_entry("scratch", BrowserRole::Docs)?;
        Ok(())
    }

    pub fn workspace_by_name(&self, name: &str) -> Option<&Workspace> {
        let id = self.by_workspace_name.get(&name.to_ascii_lowercase())?;
        self.by_workspace_id.get(id)
    }

    pub fn workspace(&self, id: WorkspaceId) -> Option<&Workspace> {
        self.by_workspace_id.get(&id)
    }

    pub fn window(&self, id: WindowId) -> Option<&Window> {
        self.by_window_id.get(&id)
    }

    pub fn cached_browser_window(&self, slug: &str, role: BrowserRole) -> Option<&Window> {
        let id = self.browser_cache.get(&(slug.to_string(), role))?;
        self.window(*id).filter(|window| window.app_id == "helium")
    }

    #[cfg(test)]
    pub fn with_browser_cache_entry(mut self, slug: &str, role: BrowserRole, id: WindowId) -> Self {
        self.browser_cache.insert((slug.to_string(), role), id);
        self
    }

    pub fn current_context(&self, cfg: &Config) -> Option<Context> {
        if let Some(id) = self.focused_workspace {
            if let Some(name) = self
                .workspace(id)
                .and_then(|workspace| workspace.name.as_deref())
            {
                if let Some(ctx) = Context::from_workspace_name(name) {
                    if cfg.context(ctx).is_some() {
                        return Some(ctx);
                    }
                }
            }
        }

        self.active_ws_by_output
            .get(&cfg.outputs.main)
            .and_then(|id| self.workspace(*id))
            .and_then(|workspace| workspace.name.as_deref())
            .and_then(Context::from_workspace_name)
            .filter(|ctx| cfg.context(*ctx).is_some())
    }

    pub fn oldest_window_by_app_id(&self, app_id: &str) -> Option<&Window> {
        self.windows
            .iter()
            .filter(|window| window.app_id == app_id)
            .min_by_key(|window| window.id)
    }

    #[allow(dead_code)]
    pub fn tiled_on_workspace(&self, ws: WorkspaceId) -> Vec<&Window> {
        let mut windows = self
            .windows
            .iter()
            .filter(|window| {
                window.workspace_id == ws && !window.is_floating && window.column.is_some()
            })
            .collect::<Vec<_>>();
        windows.sort_by_key(|window| window.column.unwrap_or((usize::MAX, usize::MAX)));
        windows
    }

    #[allow(dead_code)]
    pub fn columns_on_workspace(&self, ws: WorkspaceId) -> BTreeMap<usize, Vec<&Window>> {
        let mut columns: BTreeMap<usize, Vec<&Window>> = BTreeMap::new();
        for window in self.tiled_on_workspace(ws) {
            if let Some((column, _row)) = window.column {
                columns.entry(column).or_default().push(window);
            }
        }
        for windows in columns.values_mut() {
            windows.sort_by_key(|window| window.column.map(|(_column, row)| row).unwrap_or(0));
        }
        columns
    }

    #[allow(dead_code)]
    pub fn focused_output(&self) -> Option<&str> {
        self.focused_workspace
            .and_then(|id| self.workspace(id))
            .map(|workspace| workspace.output.as_str())
    }

    pub fn output_is_focused(&self, output: &str) -> bool {
        self.workspaces
            .iter()
            .any(|workspace| workspace.output == output && workspace.is_focused)
    }

    pub fn active_workspace_name_on_output(&self, output: &str) -> Option<&str> {
        let id = self.active_ws_by_output.get(output)?;
        self.workspace(*id)?.name.as_deref()
    }

    fn load_browser_cache_entry(&mut self, slug: &str, role: BrowserRole) -> Result<()> {
        let Some(path) = browser_cache_path(slug, role) else {
            return Ok(());
        };
        let text = match fs::read_to_string(&path) {
            Ok(text) => text,
            Err(err) if err.kind() == ErrorKind::NotFound => return Ok(()),
            Err(err) => return Err(NiriCtxError::io(&path, err)),
        };
        let mut lines = text.lines();
        let Some(id_line) = lines.next() else {
            remove_invalid_cache(&path);
            return Ok(());
        };
        let Ok(id) = id_line.parse::<u64>() else {
            remove_invalid_cache(&path);
            return Ok(());
        };
        let cached_socket = lines.next().unwrap_or_default();
        let current_socket = std::env::var("NIRI_SOCKET").unwrap_or_default();
        if !cached_socket.is_empty() && cached_socket != current_socket {
            remove_invalid_cache(&path);
            return Ok(());
        }

        let id = WindowId(id);
        if self
            .window(id)
            .is_some_and(|window| window.app_id == "helium")
        {
            self.browser_cache.insert((slug.to_string(), role), id);
        } else {
            remove_invalid_cache(&path);
        }
        Ok(())
    }
}

fn browser_cache_path(slug: &str, role: BrowserRole) -> Option<PathBuf> {
    let root = if let Some(cache) = std::env::var_os("XDG_CACHE_HOME") {
        PathBuf::from(cache)
    } else {
        PathBuf::from(std::env::var_os("HOME")?).join(".cache")
    };
    Some(
        root.join("niri-ctx")
            .join(format!("browser-{}-{}.id", slug, role.as_str())),
    )
}

fn remove_invalid_cache(path: &PathBuf) {
    if let Err(err) = fs::remove_file(path) {
        if err.kind() != ErrorKind::NotFound {
            tracing::debug!("could not remove invalid browser cache {:?}: {err}", path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::niri::{Window, Workspace};

    fn ws(id: u64, name: &str, output: &str, active: bool, focused: bool) -> Workspace {
        Workspace {
            id: WorkspaceId(id),
            name: Some(name.to_string()),
            output: output.to_string(),
            is_active: active,
            is_focused: focused,
        }
    }

    fn win(id: u64, app: &str, ws: u64, column: Option<(usize, usize)>) -> Window {
        Window {
            id: WindowId(id),
            title: String::new(),
            app_id: app.to_string(),
            pid: 1,
            workspace_id: WorkspaceId(ws),
            is_focused: false,
            is_floating: false,
            column,
            tile_height: Some(500.0),
        }
    }

    #[test]
    fn current_context_strips_devtools() {
        let cfg = Config::default_for_repo("/repo");
        let state = DesktopState::new(
            vec![
                ws(1, "UP-devtools", "DP-2", true, true),
                ws(2, "Side", "DP-1", true, false),
            ],
            vec![],
        );
        assert_eq!(state.current_context(&cfg), Some(Context::UP));
    }

    #[test]
    fn current_context_falls_back_to_main_active() {
        let cfg = Config::default_for_repo("/repo");
        let state = DesktopState::new(
            vec![
                ws(1, "unknown", "DP-2", true, true),
                ws(2, "Webroot", "DP-1", true, false),
            ],
            vec![],
        );
        assert_eq!(state.current_context(&cfg), Some(Context::Webroot));
    }

    #[test]
    fn oldest_window_by_app_id_uses_lowest_id() {
        let state = DesktopState::new(
            vec![ws(1, "UP", "DP-1", true, true)],
            vec![win(9, "helium", 1, None), win(3, "helium", 1, None)],
        );
        assert_eq!(
            state
                .oldest_window_by_app_id("helium")
                .map(|window| window.id),
            Some(WindowId(3))
        );
    }

    #[test]
    fn columns_are_sorted_by_row() {
        let state = DesktopState::new(
            vec![ws(1, "UP", "DP-1", true, true)],
            vec![
                win(4, "a", 1, Some((1, 2))),
                win(2, "b", 1, Some((1, 0))),
                win(3, "c", 1, Some((2, 0))),
            ],
        );
        let ids = state
            .columns_on_workspace(WorkspaceId(1))
            .get(&1)
            .expect("column")
            .iter()
            .map(|window| window.id)
            .collect::<Vec<_>>();
        assert_eq!(ids, vec![WindowId(2), WindowId(4)]);
    }
}
