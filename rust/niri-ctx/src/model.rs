use std::fmt;
use std::str::FromStr;
use std::time::Duration;

use crate::error::{NiriCtxError, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub enum Context {
    UP,
    Webroot,
    Sealant,
    Side,
    Admin,
}

impl Context {
    pub const ALL: [Context; 5] = [
        Context::UP,
        Context::Webroot,
        Context::Sealant,
        Context::Side,
        Context::Admin,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Context::UP => "UP",
            Context::Webroot => "Webroot",
            Context::Sealant => "Sealant",
            Context::Side => "Side",
            Context::Admin => "Admin",
        }
    }

    pub fn devtools_workspace(self) -> Option<String> {
        if self == Context::Admin {
            None
        } else {
            Some(format!("{}-devtools", self.name()))
        }
    }

    pub fn from_workspace_name(name: &str) -> Option<Self> {
        let base = name.strip_suffix("-devtools").unwrap_or(name);
        Self::ALL
            .iter()
            .copied()
            .find(|ctx| ctx.name().eq_ignore_ascii_case(base))
    }
}

impl fmt::Display for Context {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

impl FromStr for Context {
    type Err = NiriCtxError;

    fn from_str(value: &str) -> Result<Self> {
        match value.to_ascii_lowercase().as_str() {
            "up" | "job1" => Ok(Context::UP),
            "webroot" | "job2" => Ok(Context::Webroot),
            "sealant" | "side1" => Ok(Context::Sealant),
            "side" | "side2" => Ok(Context::Side),
            "admin" => Ok(Context::Admin),
            other => Err(NiriCtxError::UnknownContext(other.to_string())),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContextArg {
    Current,
    Context(Context),
}

impl FromStr for ContextArg {
    type Err = NiriCtxError;

    fn from_str(value: &str) -> Result<Self> {
        if value.eq_ignore_ascii_case("current") {
            Ok(ContextArg::Current)
        } else {
            Ok(ContextArg::Context(value.parse()?))
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub enum Role {
    All,
    Docs,
    Output,
    Editor,
    Agents,
    Logs,
    Term,
    Repo(String),
}

impl Role {
    pub fn parse(value: Option<&str>) -> Result<Self> {
        let value = value.unwrap_or("all");
        let normalized = value.to_ascii_lowercase();
        match normalized.as_str() {
            "all" => Ok(Self::All),
            "browser" | "browser-docs" | "docs" => Ok(Self::Docs),
            "browser-output" | "output" => Ok(Self::Output),
            "editor" => Ok(Self::Editor),
            "agents" => Ok(Self::Agents),
            "logs" => Ok(Self::Logs),
            "shell" | "terminal" | "term" => Ok(Self::Term),
            role if role.starts_with("repo:") => {
                let label = role.trim_start_matches("repo:");
                if is_repo_label(label) {
                    Ok(Self::Repo(label.to_string()))
                } else {
                    Err(NiriCtxError::UnknownRole(value.to_string()))
                }
            }
            _ => Err(NiriCtxError::UnknownRole(value.to_string())),
        }
    }
}

impl fmt::Display for Role {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Role::All => f.write_str("all"),
            Role::Docs => f.write_str("docs"),
            Role::Output => f.write_str("output"),
            Role::Editor => f.write_str("editor"),
            Role::Agents => f.write_str("agents"),
            Role::Logs => f.write_str("logs"),
            Role::Term => f.write_str("term"),
            Role::Repo(label) => write!(f, "repo:{label}"),
        }
    }
}

fn is_repo_label(label: &str) -> bool {
    !label.is_empty()
        && label
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-')
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, serde::Serialize)]
pub struct WindowId(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, serde::Serialize)]
pub struct WorkspaceId(pub u64);

pub type OutputName = String;

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Eq, Hash, serde::Serialize)]
pub enum WorkspaceRef {
    Name(String),
    Id(WorkspaceId),
    Index(usize),
}

impl WorkspaceRef {
    pub fn name(name: impl Into<String>) -> Self {
        Self::Name(name.into())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize)]
pub enum BrowserRole {
    Docs,
    Output,
}

impl BrowserRole {
    pub fn as_str(self) -> &'static str {
        match self {
            BrowserRole::Docs => "docs",
            BrowserRole::Output => "output",
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub enum WindowMatcher {
    AppIdExact(String),
    NewAppIdExcluding {
        app_id: String,
        before: std::collections::BTreeSet<WindowId>,
    },
    CachedId {
        id: WindowId,
        expect_app_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchFailure {
    pub command: String,
    pub app_id: String,
    pub cause: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum CommsAppKind {
    Slack,
    Telegram,
    Discord,
}

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WaitSpec {
    pub matcher: WindowMatcher,
    pub timeout: Duration,
    pub on_fail: LaunchFailure,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_context_aliases() {
        assert_eq!("job1".parse::<Context>().expect("job1"), Context::UP);
        assert_eq!("job2".parse::<Context>().expect("job2"), Context::Webroot);
        assert_eq!("side1".parse::<Context>().expect("side1"), Context::Sealant);
        assert_eq!("side2".parse::<Context>().expect("side2"), Context::Side);
        assert_eq!("admin".parse::<Context>().expect("admin"), Context::Admin);
    }

    #[test]
    fn resolves_role_aliases() {
        assert_eq!(Role::parse(None).expect("default"), Role::All);
        assert_eq!(Role::parse(Some("browser")).expect("browser"), Role::Docs);
        assert_eq!(
            Role::parse(Some("browser-output")).expect("output"),
            Role::Output
        );
        assert_eq!(Role::parse(Some("shell")).expect("shell"), Role::Term);
        assert_eq!(
            Role::parse(Some("repo:Mono")).expect("repo"),
            Role::Repo("mono".to_string())
        );
        assert!(Role::parse(Some("repo:bad.label")).is_err());
    }
}
