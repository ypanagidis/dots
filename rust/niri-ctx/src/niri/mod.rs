pub mod fake;
pub mod ipc;

use std::time::Duration;

use crate::error::Result;
use crate::model::{OutputName, WindowId, WindowMatcher, WorkspaceId, WorkspaceRef};

pub use niri_ipc::SizeChange;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Workspace {
    pub id: WorkspaceId,
    pub name: Option<String>,
    pub output: OutputName,
    pub is_active: bool,
    pub is_focused: bool,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Window {
    pub id: WindowId,
    pub title: String,
    pub app_id: String,
    pub pid: u32,
    pub workspace_id: WorkspaceId,
    pub is_focused: bool,
    pub is_floating: bool,
    pub column: Option<(usize, usize)>,
    /// Tile height in logical px when tiled; used to detect unequal comms stacks.
    pub tile_height: Option<f64>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq)]
pub enum NiriAction {
    FocusOutput {
        output: OutputName,
    },
    FocusWorkspace {
        reference: WorkspaceRef,
    },
    FocusWindow {
        id: WindowId,
    },
    MoveWindowToWorkspace {
        window_id: WindowId,
        reference: WorkspaceRef,
        focus: bool,
    },
    MoveColumnToIndex {
        index: usize,
    },
    MoveWorkspaceToIndex {
        reference: Option<WorkspaceRef>,
        index: usize,
    },
    ExpelWindowFromColumn,
    ConsumeWindowIntoColumn,
    SetColumnWidth {
        change: SizeChange,
    },
    SetWindowHeight {
        id: Option<WindowId>,
        change: SizeChange,
    },
}

#[allow(dead_code)]
pub trait NiriClient {
    fn workspaces(&mut self) -> Result<Vec<Workspace>>;
    fn windows(&mut self) -> Result<Vec<Window>>;
    fn action(&mut self, action: NiriAction) -> Result<()>;
    fn wait_for_window(
        &mut self,
        matcher: &WindowMatcher,
        timeout: Duration,
    ) -> Result<Option<Window>>;
    fn note_spawn(&mut self, _app_id: &str, _title: &str) {}
}
