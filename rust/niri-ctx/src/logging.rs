use std::fs::{self, OpenOptions};
use std::path::PathBuf;

use tracing_subscriber::fmt::writer::BoxMakeWriter;

use crate::error::{NiriCtxError, Result};

pub fn init(verbose: bool) -> Result<()> {
    let log_path = log_path()?;
    if let Some(parent) = log_path.parent() {
        fs::create_dir_all(parent).map_err(|source| NiriCtxError::io(parent, source))?;
    }
    rotate_if_needed(&log_path)?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .map_err(|source| NiriCtxError::io(&log_path, source))?;
    let file_writer = BoxMakeWriter::new(file);
    let subscriber = tracing_subscriber::fmt()
        .with_ansi(false)
        .with_target(false)
        .with_writer(file_writer)
        .finish();
    tracing::subscriber::set_global_default(subscriber)
        .map_err(|err| NiriCtxError::Config(format!("initialize tracing: {err}")))?;
    if verbose {
        eprintln!("niri-ctx logging to {}", log_path.display());
    }
    Ok(())
}

fn rotate_if_needed(path: &PathBuf) -> Result<()> {
    let Ok(text) = fs::read_to_string(path) else {
        return Ok(());
    };
    let lines = text.lines().collect::<Vec<_>>();
    if lines.len() <= 2400 {
        return Ok(());
    }
    let keep_from = lines.len().saturating_sub(2000);
    let mut trimmed = lines[keep_from..].join("\n");
    trimmed.push('\n');
    fs::write(path, trimmed).map_err(|source| NiriCtxError::io(path, source))
}

fn log_path() -> Result<PathBuf> {
    if let Some(cache) = std::env::var_os("XDG_CACHE_HOME") {
        return Ok(PathBuf::from(cache).join("niri-ctx/log"));
    }
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| NiriCtxError::Config("HOME is not set".to_string()))?;
    Ok(home.join(".cache/niri-ctx/log"))
}
