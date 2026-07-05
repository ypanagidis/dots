use std::path::PathBuf;

use crate::planner::Effect;

pub type Result<T> = std::result::Result<T, NiriCtxError>;

#[allow(dead_code)]
#[derive(Debug, thiserror::Error)]
pub enum NiriCtxError {
    #[error("configuration error: {0}")]
    Config(String),
    #[error("ipc error: {0}")]
    Ipc(String),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("launch failed for {command} ({app_id}): {cause}")]
    LaunchFailed {
        command: String,
        app_id: String,
        cause: String,
    },
    #[error("command {command} did not converge after {iterations} iterations; remaining effects: {remaining_effects:?}")]
    NoConverge {
        command: String,
        iterations: usize,
        remaining_effects: Vec<Effect>,
    },
    #[error("unknown context: {0}")]
    UnknownContext(String),
    #[error("unknown role: {0}")]
    UnknownRole(String),
    #[error("herdr unavailable: {0}")]
    HerdrUnavailable(String),
    #[error("phase 1 is read-only; mutating effect refused: {0:?}")]
    ReadOnlyEffect(Box<Effect>),
    #[error("not implemented in Rust yet, use bash")]
    NotImplementedUseBash,
    #[error("io error at {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error(transparent)]
    Anyhow(#[from] anyhow::Error),
}

impl NiriCtxError {
    pub fn io(path: impl Into<PathBuf>, source: std::io::Error) -> Self {
        Self::Io {
            path: path.into(),
            source,
        }
    }
}
