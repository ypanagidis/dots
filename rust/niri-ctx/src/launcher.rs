use crate::config::Config;
use crate::model::{Context, Role};

#[allow(dead_code)]
pub fn terminal_argv(
    cfg: &Config,
    ctx: Context,
    role: &Role,
    app_id: &str,
    title: &str,
) -> Vec<String> {
    match cfg.terminal.program.as_str() {
        "alacritty" => vec![
            "alacritty".to_string(),
            "--class".to_string(),
            format!("{app_id},{app_id}"),
            "--title".to_string(),
            title.to_string(),
            "-e".to_string(),
            cfg.behavior.bash_fallback.display().to_string(),
            "--tmux-role".to_string(),
            ctx.to_string(),
            role.to_string(),
        ],
        "ghostty" => vec![
            "ghostty".to_string(),
            "--gtk-single-instance=false".to_string(),
            format!("--class={app_id}"),
            format!("--title={title}"),
            "-e".to_string(),
            cfg.behavior.bash_fallback.display().to_string(),
            "--tmux-role".to_string(),
            ctx.to_string(),
            role.to_string(),
        ],
        other => vec![other.to_string()],
    }
}
