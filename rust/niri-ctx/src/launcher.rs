use std::path::PathBuf;
use std::process::{Child, Command, ExitStatus, Stdio};

use std::os::unix::process::CommandExt;

use crate::config::{CommsAppConfig, Config};
use crate::error::{NiriCtxError, Result};
use crate::model::{BrowserRole, Context, Role};

#[derive(Debug)]
pub struct LaunchedProcess {
    pub argv: Vec<String>,
    pub app_id: String,
    child: Option<Child>,
    fake_status: Option<ExitStatus>,
}

impl LaunchedProcess {
    pub fn pid(&self) -> Option<u32> {
        self.child.as_ref().map(Child::id)
    }

    pub fn try_wait(&mut self) -> Result<Option<ExitStatus>> {
        if self.fake_status.is_some() {
            return Ok(self.fake_status);
        }
        match &mut self.child {
            Some(child) => child
                .try_wait()
                .map_err(|source| NiriCtxError::io(self.argv.join(" "), source)),
            None => Ok(None),
        }
    }

    #[cfg(test)]
    pub fn fake(argv: Vec<String>, app_id: String, status: Option<ExitStatus>) -> Self {
        Self {
            argv,
            app_id,
            child: None,
            fake_status: status,
        }
    }
}

pub trait Launcher {
    fn spawn_terminal(
        &mut self,
        cfg: &Config,
        ctx: Context,
        role: &Role,
        app_id: &str,
        title: &str,
    ) -> Result<LaunchedProcess>;
    fn spawn_browser(
        &mut self,
        cfg: &Config,
        ctx: Context,
        role: BrowserRole,
        profile: &str,
    ) -> Result<LaunchedProcess>;
    fn spawn_comms_app(&mut self, cfg: &Config, app: &str) -> Result<Option<LaunchedProcess>>;
    fn spawn_spotify(&mut self, cfg: &Config) -> Result<LaunchedProcess>;
    fn kill_class_marked(&mut self, app_id: &str) -> Result<()>;
}

#[derive(Debug, Default)]
pub struct ProcessLauncher;

impl Launcher for ProcessLauncher {
    fn spawn_terminal(
        &mut self,
        cfg: &Config,
        ctx: Context,
        role: &Role,
        app_id: &str,
        title: &str,
    ) -> Result<LaunchedProcess> {
        let argv = if app_id == "dev.yiannis.niri.scratch.term" {
            plain_terminal_argv(cfg, app_id, title)?
        } else {
            terminal_argv(cfg, ctx, role, app_id, title)?
        };
        spawn(argv, app_id.to_string())
    }

    fn spawn_browser(
        &mut self,
        cfg: &Config,
        _ctx: Context,
        _role: BrowserRole,
        profile: &str,
    ) -> Result<LaunchedProcess> {
        let bin = helium_bin(cfg)?;
        spawn(
            vec![
                bin,
                format!("--profile-directory={profile}"),
                "--new-window".to_string(),
                "about:blank".to_string(),
            ],
            "helium".to_string(),
        )
    }

    fn spawn_comms_app(&mut self, cfg: &Config, app: &str) -> Result<Option<LaunchedProcess>> {
        let Some(app_cfg) = cfg
            .comms
            .apps
            .iter()
            .find(|candidate| candidate.name == app)
        else {
            return Err(NiriCtxError::Config(format!("unknown comms app {app}")));
        };
        let Some(argv) = first_available_argv(&app_cfg.launch) else {
            tracing::info!(app, "comms app not installed; skipping");
            return Ok(None);
        };
        spawn(argv, app_cfg.app_id.clone()).map(Some)
    }

    fn spawn_spotify(&mut self, cfg: &Config) -> Result<LaunchedProcess> {
        let Some(argv) = first_available_argv(&cfg.ambient.spotify_launch) else {
            return Err(NiriCtxError::LaunchFailed {
                command: "spotify-launcher or spotify".to_string(),
                app_id: cfg.ambient.spotify_app_id.clone(),
                cause: "no configured spotify launcher binary was found".to_string(),
            });
        };
        spawn(argv, cfg.ambient.spotify_app_id.clone())
    }

    fn kill_class_marked(&mut self, app_id: &str) -> Result<()> {
        let pattern = format!("-class[= ]{}", app_id.replace('.', "\\."));
        let status = Command::new("pkill")
            .arg("-f")
            .arg("--")
            .arg(&pattern)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map_err(|source| NiriCtxError::io("pkill", source))?;
        tracing::info!(app_id, ?status, "self-heal class kill");
        Ok(())
    }
}

pub fn terminal_argv(
    cfg: &Config,
    ctx: Context,
    role: &Role,
    app_id: &str,
    title: &str,
) -> Result<Vec<String>> {
    let dispatcher = installed_dispatcher_path()?;
    Ok(match cfg.terminal.program.as_str() {
        "alacritty" => vec![
            "alacritty".to_string(),
            "--class".to_string(),
            format!("{app_id},{app_id}"),
            "--title".to_string(),
            title.to_string(),
            "-e".to_string(),
            dispatcher.display().to_string(),
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
            dispatcher.display().to_string(),
            "--tmux-role".to_string(),
            ctx.to_string(),
            role.to_string(),
        ],
        other => {
            return Err(NiriCtxError::Config(format!(
                "unsupported terminal program {other}; use ghostty or alacritty"
            )));
        }
    })
}

fn plain_terminal_argv(cfg: &Config, app_id: &str, title: &str) -> Result<Vec<String>> {
    Ok(match cfg.terminal.program.as_str() {
        "alacritty" => vec![
            "alacritty".to_string(),
            "--class".to_string(),
            format!("{app_id},{app_id}"),
            "--title".to_string(),
            title.to_string(),
        ],
        "ghostty" => vec![
            "ghostty".to_string(),
            "--gtk-single-instance=false".to_string(),
            format!("--class={app_id}"),
            format!("--title={title}"),
        ],
        other => {
            return Err(NiriCtxError::Config(format!(
                "unsupported terminal program {other}; use ghostty or alacritty"
            )));
        }
    })
}

fn spawn(argv: Vec<String>, app_id: String) -> Result<LaunchedProcess> {
    let mut command = Command::new(&argv[0]);
    command.args(&argv[1..]);
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    unsafe {
        command.pre_exec(|| {
            rustix::process::setsid()
                .map(|_| ())
                .map_err(std::io::Error::from)
        });
    }
    let child = command
        .spawn()
        .map_err(|source| NiriCtxError::io(argv.join(" "), source))?;
    tracing::info!(?argv, pid = child.id(), "spawned process");
    Ok(LaunchedProcess {
        argv,
        app_id,
        child: Some(child),
        fake_status: None,
    })
}

fn helium_bin(cfg: &Config) -> Result<String> {
    if cfg.browser.bin.is_file() {
        return Ok(cfg.browser.bin.display().to_string());
    }
    which("helium")
        .map(|path| path.display().to_string())
        .ok_or_else(|| NiriCtxError::LaunchFailed {
            command: cfg.browser.bin.display().to_string(),
            app_id: "helium".to_string(),
            cause: "helium is not installed and configured browser.bin is not executable"
                .to_string(),
        })
}

fn first_available_argv(candidates: &[Vec<String>]) -> Option<Vec<String>> {
    candidates.iter().find_map(|argv| {
        let bin = argv.first()?;
        if executable_exists(bin) {
            Some(argv.clone())
        } else {
            None
        }
    })
}

fn executable_exists(bin: &str) -> bool {
    let path = PathBuf::from(bin);
    if path.components().count() > 1 {
        path.is_file()
    } else {
        which(bin).is_some()
    }
}

fn which(bin: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join(bin))
        .find(|candidate| candidate.is_file())
}

fn installed_dispatcher_path() -> Result<PathBuf> {
    std::env::current_exe()
        .map_err(|source| NiriCtxError::io("resolve current niri-ctx executable", source))
}

#[allow(dead_code)]
fn _uses_app_config(_app: &CommsAppConfig) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_reentry_uses_the_running_dispatcher() {
        assert_eq!(
            installed_dispatcher_path().unwrap(),
            std::env::current_exe().unwrap()
        );
    }
}
