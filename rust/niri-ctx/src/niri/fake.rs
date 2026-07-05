use std::time::Duration;

use crate::error::Result;
use crate::model::{WindowMatcher, WorkspaceRef};

use super::{NiriAction, NiriClient, Window, Workspace};

#[allow(dead_code)]
#[derive(Debug, Clone, Default)]
pub struct FakeNiriClient {
    pub workspaces: Vec<Workspace>,
    pub windows: Vec<Window>,
    pub actions: Vec<NiriAction>,
}

impl FakeNiriClient {
    #[allow(dead_code)]
    pub fn new(workspaces: Vec<Workspace>, windows: Vec<Window>) -> Self {
        Self {
            workspaces,
            windows,
            actions: Vec::new(),
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
        if let NiriAction::FocusWorkspace {
            reference: WorkspaceRef::Name(name),
        } = &action
        {
            for workspace in &mut self.workspaces {
                workspace.is_focused = workspace.name.as_deref() == Some(name.as_str());
            }
        }
        self.actions.push(action);
        Ok(())
    }

    fn wait_for_window(
        &mut self,
        matcher: &WindowMatcher,
        _timeout: Duration,
    ) -> Result<Option<Window>> {
        Ok(self
            .windows
            .iter()
            .find(|window| matches_window(window, matcher))
            .cloned())
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
