use std::time::Duration;

use crate::error::Result;
use crate::model::{WindowId, WindowMatcher, WorkspaceId, WorkspaceRef};

use super::{NiriAction, NiriClient, Window, Workspace};

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct FakeNiriClient {
    pub workspaces: Vec<Workspace>,
    pub windows: Vec<Window>,
    pub actions: Vec<NiriAction>,
    pub map_spawns: bool,
    pub wait_never_maps: bool,
    next_window_id: u64,
}

impl Default for FakeNiriClient {
    fn default() -> Self {
        Self {
            workspaces: Vec::new(),
            windows: Vec::new(),
            actions: Vec::new(),
            map_spawns: true,
            wait_never_maps: false,
            next_window_id: 100,
        }
    }
}

impl FakeNiriClient {
    #[allow(dead_code)]
    pub fn new(workspaces: Vec<Workspace>, windows: Vec<Window>) -> Self {
        let next_window_id = windows.iter().map(|window| window.id.0).max().unwrap_or(99) + 1;
        Self {
            workspaces,
            windows,
            actions: Vec::new(),
            map_spawns: true,
            wait_never_maps: false,
            next_window_id,
        }
    }

    fn focused_workspace_id(&self) -> Option<WorkspaceId> {
        self.workspaces
            .iter()
            .find(|workspace| workspace.is_focused)
            .map(|workspace| workspace.id)
            .or_else(|| {
                self.workspaces
                    .iter()
                    .find(|workspace| workspace.is_active)
                    .map(|workspace| workspace.id)
            })
    }

    fn workspace_id_for_ref(&self, reference: &WorkspaceRef) -> Option<WorkspaceId> {
        match reference {
            WorkspaceRef::Name(name) => self
                .workspaces
                .iter()
                .find(|workspace| workspace.name.as_deref() == Some(name.as_str()))
                .map(|workspace| workspace.id),
            WorkspaceRef::Id(id) => Some(*id),
            WorkspaceRef::Index(index) => self
                .workspaces
                .iter()
                .filter(|workspace| workspace.is_active)
                .nth(index.saturating_sub(1))
                .map(|workspace| workspace.id),
        }
    }

    fn focus_workspace_id(&mut self, id: WorkspaceId) {
        let output = self
            .workspaces
            .iter()
            .find(|workspace| workspace.id == id)
            .map(|workspace| workspace.output.clone());
        for workspace in &mut self.workspaces {
            if workspace.id == id {
                workspace.is_focused = true;
                workspace.is_active = true;
            } else if output.as_deref() == Some(workspace.output.as_str()) {
                workspace.is_active = false;
                workspace.is_focused = false;
            } else {
                workspace.is_focused = false;
            }
        }
        for window in &mut self.windows {
            window.is_focused = false;
        }
    }

    fn focus_window_id(&mut self, id: WindowId) {
        let ws = self
            .windows
            .iter()
            .find(|window| window.id == id)
            .map(|window| window.workspace_id);
        for window in &mut self.windows {
            window.is_focused = window.id == id;
        }
        if let Some(ws) = ws {
            self.focus_workspace_id(ws);
            for window in &mut self.windows {
                window.is_focused = window.id == id;
            }
        }
    }
}

impl NiriClient for FakeNiriClient {
    fn workspaces(&mut self) -> Result<Vec<Workspace>> {
        Ok(self.workspaces.clone())
    }

    fn windows(&mut self) -> Result<Vec<Window>> {
        Ok(self.windows.clone())
    }

    fn action(&mut self, action: NiriAction) -> Result<()> {
        match &action {
            NiriAction::FocusOutput { output } => {
                if let Some(id) = self
                    .workspaces
                    .iter()
                    .find(|workspace| workspace.output == *output && workspace.is_active)
                    .map(|workspace| workspace.id)
                {
                    self.focus_workspace_id(id);
                }
            }
            NiriAction::FocusWorkspace { reference } => {
                if let Some(id) = self.workspace_id_for_ref(reference) {
                    self.focus_workspace_id(id);
                }
            }
            NiriAction::FocusWindow { id } => self.focus_window_id(*id),
            NiriAction::MoveWindowToWorkspace {
                window_id,
                reference,
                focus,
            } => {
                if let Some(ws) = self.workspace_id_for_ref(reference) {
                    let column = next_free_column(&self.windows, ws);
                    if let Some(window) = self
                        .windows
                        .iter_mut()
                        .find(|window| window.id == *window_id)
                    {
                        window.workspace_id = ws;
                        window.column = Some((column, 1));
                    }
                    if *focus {
                        self.focus_window_id(*window_id);
                    }
                }
            }
            NiriAction::MoveColumnToIndex { index } => {
                if let Some(id) = self
                    .windows
                    .iter()
                    .find(|window| window.is_focused)
                    .map(|window| window.id)
                {
                    if let Some(window) = self.windows.iter_mut().find(|window| window.id == id) {
                        window.column =
                            Some((*index, window.column.map(|(_, row)| row).unwrap_or(1)));
                    }
                }
            }
            NiriAction::ExpelWindowFromColumn => {
                if let Some(id) = self
                    .windows
                    .iter()
                    .find(|window| window.is_focused)
                    .map(|window| window.id)
                {
                    let ws = self
                        .windows
                        .iter()
                        .find(|window| window.id == id)
                        .map(|window| window.workspace_id);
                    if let Some(ws) = ws {
                        let col = next_free_column(&self.windows, ws);
                        if let Some(window) = self.windows.iter_mut().find(|window| window.id == id)
                        {
                            window.column = Some((col, 1));
                        }
                    }
                }
            }
            NiriAction::ConsumeWindowIntoColumn => {
                let focused = self
                    .windows
                    .iter()
                    .find(|window| window.is_focused)
                    .and_then(|window| Some((window.workspace_id, window.column?.0)));
                if let Some((ws, col)) = focused {
                    let right = self
                        .windows
                        .iter()
                        .filter(|window| window.workspace_id == ws)
                        .filter_map(|window| window.column.map(|(c, r)| (c, r, window.id)))
                        .filter(|(c, _, _)| *c > col)
                        .min()
                        .map(|(_, _, id)| id);
                    if let Some(right) = right {
                        let row = self
                            .windows
                            .iter()
                            .filter(|window| {
                                window.workspace_id == ws
                                    && window.column.map(|(c, _)| c) == Some(col)
                            })
                            .count()
                            + 1;
                        if let Some(window) =
                            self.windows.iter_mut().find(|window| window.id == right)
                        {
                            window.column = Some((col, row));
                        }
                    }
                }
            }
            NiriAction::SetColumnWidth { .. } | NiriAction::SetWindowHeight { .. } => {}
            NiriAction::MoveWorkspaceToIndex { .. } => {}
        }
        self.actions.push(action);
        Ok(())
    }

    fn wait_for_window(
        &mut self,
        matcher: &WindowMatcher,
        _timeout: Duration,
    ) -> Result<Option<Window>> {
        if self.wait_never_maps {
            return Ok(None);
        }
        Ok(self
            .windows
            .iter()
            .find(|window| matches_window(window, matcher))
            .cloned())
    }

    fn note_spawn(&mut self, app_id: &str, title: &str) {
        if !self.map_spawns {
            return;
        }
        let Some(ws) = self.focused_workspace_id() else {
            return;
        };
        let id = WindowId(self.next_window_id);
        self.next_window_id += 1;
        let column = next_free_column(&self.windows, ws);
        for window in &mut self.windows {
            window.is_focused = false;
        }
        self.windows.push(Window {
            id,
            title: title.to_string(),
            app_id: app_id.to_string(),
            pid: id.0 as u32,
            workspace_id: ws,
            is_focused: true,
            is_floating: false,
            column: Some((column, 1)),
        });
    }
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

fn next_free_column(windows: &[Window], ws: WorkspaceId) -> usize {
    windows
        .iter()
        .filter(|window| window.workspace_id == ws)
        .filter_map(|window| window.column.map(|(column, _)| column))
        .max()
        .unwrap_or(0)
        + 1
}
