use crate::config::Config;
use crate::error::{NiriCtxError, Result};
use crate::state::DesktopState;

pub fn print_current(cfg: &Config, state: &DesktopState) -> Result<()> {
    let ctx = state
        .current_context(cfg)
        .ok_or_else(|| NiriCtxError::UnknownContext("current".to_string()))?;
    println!("{ctx}");
    Ok(())
}
