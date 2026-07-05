use crate::config::Config;
use crate::error::Result;
use crate::state::DesktopState;

#[derive(serde::Serialize)]
struct Inspect<'a> {
    config: &'a Config,
    state: &'a DesktopState,
}

pub fn print(cfg: &Config, state: &DesktopState, json: bool) -> Result<()> {
    if json {
        let value = Inspect { config: cfg, state };
        let text = serde_json::to_string_pretty(&value)?;
        println!("{text}");
    } else {
        println!("current_context={:?}", state.current_context(cfg));
        println!("workspaces={}", state.workspaces.len());
        println!("windows={}", state.windows.len());
    }
    Ok(())
}
