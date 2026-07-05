use std::fs;
use std::path::PathBuf;
use std::process::ExitStatus;

use crate::config::Config;
use crate::error::{NiriCtxError, Result};
use crate::launcher::{LaunchedProcess, Launcher};
use crate::model::{BrowserRole, Context, Role, WindowId, WindowMatcher};
use crate::niri::{NiriAction, NiriClient, Window};
use crate::planner::Effect;
use crate::session::{role_session_name, SessionBackend};

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutorMode {
    Live,
    DryRun,
}

#[derive(Debug, Clone)]
enum LastSpawn {
    Terminal {
        ctx: Context,
        role: Role,
        app_id: String,
        title: String,
        session: Option<String>,
        session_was_fresh: bool,
    },
    Browser {
        ctx: Context,
        role: BrowserRole,
        profile: String,
    },
    Comms {
        app: String,
    },
    Spotify,
}

pub struct Executor<'a> {
    cfg: &'a Config,
    mode: ExecutorMode,
    client: &'a mut dyn NiriClient,
    launcher: &'a mut dyn Launcher,
    sessions: &'a mut dyn SessionBackend,
    last_spawn: Option<LastSpawn>,
    last_process: Option<LaunchedProcess>,
    last_window: Option<Window>,
    skip_next_wait: bool,
}

impl<'a> Executor<'a> {
    pub fn new(
        cfg: &'a Config,
        mode: ExecutorMode,
        client: &'a mut dyn NiriClient,
        launcher: &'a mut dyn Launcher,
        sessions: &'a mut dyn SessionBackend,
    ) -> Self {
        Self {
            cfg,
            mode,
            client,
            launcher,
            sessions,
            last_spawn: None,
            last_process: None,
            last_window: None,
            skip_next_wait: false,
        }
    }

    pub fn run(&mut self, effects: &[Effect]) -> Result<()> {
        match self.mode {
            ExecutorMode::DryRun => {
                for effect in effects {
                    println!("{effect:?}");
                }
                Ok(())
            }
            ExecutorMode::Live => {
                for effect in effects {
                    tracing::info!(?effect, "execute effect");
                    self.execute(effect)?;
                }
                Ok(())
            }
        }
    }

    fn execute(&mut self, effect: &Effect) -> Result<()> {
        match effect {
            Effect::FocusOutput { output } => self.client.action(NiriAction::FocusOutput {
                output: output.clone(),
            }),
            Effect::FocusWorkspace { ws, .. } => self.client.action(NiriAction::FocusWorkspace {
                reference: ws.clone(),
            }),
            Effect::FocusWindow { id } => self.client.action(NiriAction::FocusWindow { id: *id }),
            Effect::MoveWindowToWorkspace { id, ws, focus } => {
                self.client.action(NiriAction::MoveWindowToWorkspace {
                    window_id: *id,
                    reference: ws.clone(),
                    focus: *focus,
                })
            }
            Effect::MoveColumnToIndex { index } => self
                .client
                .action(NiriAction::MoveColumnToIndex { index: *index }),
            Effect::ExpelWindowFromColumn => self.client.action(NiriAction::ExpelWindowFromColumn),
            Effect::ConsumeWindowIntoColumn => {
                self.client.action(NiriAction::ConsumeWindowIntoColumn)
            }
            Effect::SetColumnWidth { change } => self
                .client
                .action(NiriAction::SetColumnWidth { change: *change }),
            Effect::SetWindowHeight { id, change } => {
                self.client.action(NiriAction::SetWindowHeight {
                    id: Some(*id),
                    change: *change,
                })
            }
            Effect::SpawnTerminal {
                ctx,
                role,
                app_id,
                title,
            } => {
                let (session, session_was_fresh) =
                    terminal_session_fresh(self.sessions, *ctx, role)?;
                let process = self
                    .launcher
                    .spawn_terminal(self.cfg, *ctx, role, app_id, title)?;
                self.client.note_spawn(app_id, title);
                self.last_spawn = Some(LastSpawn::Terminal {
                    ctx: *ctx,
                    role: role.clone(),
                    app_id: app_id.clone(),
                    title: title.clone(),
                    session,
                    session_was_fresh,
                });
                self.last_process = Some(process);
                self.skip_next_wait = false;
                Ok(())
            }
            Effect::SpawnBrowser { ctx, role, profile } => {
                let process = self
                    .launcher
                    .spawn_browser(self.cfg, *ctx, *role, profile)?;
                self.client.note_spawn("helium", "helium");
                self.last_spawn = Some(LastSpawn::Browser {
                    ctx: *ctx,
                    role: *role,
                    profile: profile.clone(),
                });
                self.last_process = Some(process);
                self.skip_next_wait = false;
                Ok(())
            }
            Effect::SpawnCommsApp { app } => {
                if let Some(process) = self.launcher.spawn_comms_app(self.cfg, app)? {
                    let app_id = process.app_id.clone();
                    self.client.note_spawn(&app_id, app);
                    self.last_process = Some(process);
                    self.skip_next_wait = false;
                } else {
                    self.last_process = None;
                    self.skip_next_wait = true;
                }
                self.last_spawn = Some(LastSpawn::Comms { app: app.clone() });
                Ok(())
            }
            Effect::SpawnSpotify => {
                let process = self.launcher.spawn_spotify(self.cfg)?;
                self.client
                    .note_spawn(&self.cfg.ambient.spotify_app_id, "Spotify");
                self.last_spawn = Some(LastSpawn::Spotify);
                self.last_process = Some(process);
                self.skip_next_wait = false;
                Ok(())
            }
            Effect::WaitForWindow {
                matcher,
                timeout,
                on_fail,
            } => {
                if self.skip_next_wait {
                    self.skip_next_wait = false;
                    return Ok(());
                }
                if let Some(window) = self.client.wait_for_window(matcher, *timeout)? {
                    self.last_window = Some(window);
                    return Ok(());
                }
                tracing::info!(?matcher, ?timeout, "wait timed out; retrying launch once");
                self.self_heal_after_timeout(on_fail)?;
                let Some(window) = self.client.wait_for_window(matcher, *timeout)? else {
                    return Err(self.launch_failure(on_fail, *timeout)?);
                };
                self.last_window = Some(window);
                Ok(())
            }
            Effect::WriteBrowserCache { ctx_slug, role, id } => {
                let id = id.or_else(|| self.last_window.as_ref().map(|window| window.id));
                if let Some(id) = id {
                    write_browser_cache(ctx_slug, *role, id)?;
                }
                Ok(())
            }
            Effect::Log { level, msg } => {
                tracing::info!(%level, %msg);
                Ok(())
            }
            Effect::Fail { diag } => Err(NiriCtxError::Config(diag.clone())),
        }
    }

    fn self_heal_after_timeout(&mut self, on_fail: &crate::model::LaunchFailure) -> Result<()> {
        if let Some(process) = &self.last_process {
            self.launcher.kill_class_marked(&process.app_id)?;
        } else {
            self.launcher.kill_class_marked(&on_fail.app_id)?;
        }
        if let Some(LastSpawn::Terminal {
            session: Some(session),
            session_was_fresh: true,
            ..
        }) = &self.last_spawn
        {
            self.sessions.reap_fresh_session(session)?;
        }
        let Some(spawn) = self.last_spawn.clone() else {
            return Ok(());
        };
        match spawn {
            LastSpawn::Terminal {
                ctx,
                role,
                app_id,
                title,
                session,
                session_was_fresh,
            } => {
                let process = self
                    .launcher
                    .spawn_terminal(self.cfg, ctx, &role, &app_id, &title)?;
                self.client.note_spawn(&app_id, &title);
                self.last_process = Some(process);
                self.last_spawn = Some(LastSpawn::Terminal {
                    ctx,
                    role,
                    app_id,
                    title,
                    session,
                    session_was_fresh,
                });
            }
            LastSpawn::Browser { ctx, role, profile } => {
                let process = self.launcher.spawn_browser(self.cfg, ctx, role, &profile)?;
                self.client.note_spawn("helium", "helium");
                self.last_process = Some(process);
                self.last_spawn = Some(LastSpawn::Browser { ctx, role, profile });
            }
            LastSpawn::Comms { app } => {
                self.last_process = self.launcher.spawn_comms_app(self.cfg, &app)?;
                if let Some(process) = &self.last_process {
                    self.client.note_spawn(&process.app_id, &app);
                }
                self.last_spawn = Some(LastSpawn::Comms { app });
            }
            LastSpawn::Spotify => {
                let process = self.launcher.spawn_spotify(self.cfg)?;
                self.client
                    .note_spawn(&self.cfg.ambient.spotify_app_id, "Spotify");
                self.last_process = Some(process);
                self.last_spawn = Some(LastSpawn::Spotify);
            }
        }
        Ok(())
    }

    fn launch_failure(
        &mut self,
        on_fail: &crate::model::LaunchFailure,
        timeout: std::time::Duration,
    ) -> Result<NiriCtxError> {
        if let Some(process) = &mut self.last_process {
            let pid = process.pid();
            let argv = process.argv.join(" ");
            if let Some(status) = process.try_wait()? {
                return Ok(NiriCtxError::LaunchFailed {
                    command: argv,
                    app_id: on_fail.app_id.clone(),
                    cause: process_exited_cause(status),
                });
            }
            return Ok(NiriCtxError::LaunchFailed {
                command: argv,
                app_id: on_fail.app_id.clone(),
                cause: format!(
                    "pid {} alive, app-id {} never appeared within {}s, attempt 2/2",
                    pid.map_or_else(|| "?".to_string(), |pid| pid.to_string()),
                    on_fail.app_id,
                    timeout.as_secs()
                ),
            });
        }
        Ok(NiriCtxError::LaunchFailed {
            command: on_fail.command.clone(),
            app_id: on_fail.app_id.clone(),
            cause: on_fail.cause.clone(),
        })
    }
}

pub fn focus_only(effects: &[Effect]) -> Vec<Effect> {
    effects
        .iter()
        .filter(|effect| {
            matches!(
                effect,
                Effect::FocusOutput { .. }
                    | Effect::FocusWorkspace { .. }
                    | Effect::FocusWindow { .. }
            )
        })
        .cloned()
        .collect()
}

fn terminal_session_fresh(
    sessions: &mut dyn SessionBackend,
    ctx: Context,
    role: &Role,
) -> Result<(Option<String>, bool)> {
    let session = role_session_name(ctx, role)?;
    let existed = sessions.session_exists(&session)?;
    Ok((Some(session), !existed))
}

fn process_exited_cause(status: ExitStatus) -> String {
    match status.code() {
        Some(code) => format!("process exited with code {code}"),
        None => "process exited after signal".to_string(),
    }
}

fn write_browser_cache(slug: &str, role: BrowserRole, id: WindowId) -> Result<()> {
    let path = browser_cache_path(slug, role)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|source| NiriCtxError::io(parent, source))?;
    }
    let tmp = path.with_extension(format!("{}.tmp", std::process::id()));
    let socket = std::env::var("NIRI_SOCKET").unwrap_or_default();
    fs::write(&tmp, format!("{}\n{}\n", id.0, socket))
        .map_err(|source| NiriCtxError::io(&tmp, source))?;
    fs::rename(&tmp, &path).map_err(|source| NiriCtxError::io(&path, source))
}

fn browser_cache_path(slug: &str, role: BrowserRole) -> Result<PathBuf> {
    let root = if let Some(cache) = std::env::var_os("XDG_CACHE_HOME") {
        PathBuf::from(cache)
    } else {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| NiriCtxError::Config("HOME is not set".to_string()))?;
        home.join(".cache")
    };
    Ok(root
        .join("niri-ctx")
        .join(format!("browser-{}-{}.id", slug, role.as_str())))
}

#[allow(dead_code)]
fn _matcher_name(matcher: &WindowMatcher) -> &'static str {
    match matcher {
        WindowMatcher::AppIdExact(_) => "app-id",
        WindowMatcher::NewAppIdExcluding { .. } => "new-app-id",
        WindowMatcher::CachedId { .. } => "cached-id",
    }
}
