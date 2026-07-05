mod cli;
mod commands;
mod config;
mod error;
mod executor;
mod launcher;
mod lock;
mod logging;
mod matchers;
mod model;
mod niri;
mod planner;
mod session;
mod state;

use std::os::unix::process::CommandExt;
use std::process::{Command as ProcessCommand, ExitCode};
use std::thread;
use std::time::Duration;

use clap::Parser;

use crate::cli::{Cli, Command};
use crate::commands::goal_from_command;
use crate::config::Config;
use crate::error::{NiriCtxError, Result};
use crate::executor::{focus_only, Executor, ExecutorMode};
use crate::launcher::ProcessLauncher;
use crate::lock::{GlobalLock, LockAttempt};
use crate::model::Role;
use crate::niri::ipc::IpcNiriClient;
use crate::niri::NiriClient;
use crate::planner::{plan, resolve_context_arg, Effect, Goal};
use crate::session::{NoopSessionBackend, RealSessionBackend, SessionBackend};
use crate::state::DesktopState;

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<u8> {
    let cli = Cli::parse();
    let cfg = Config::load()?;
    logging::init(cli.verbose)?;

    if let Some(args) = cli.tmux_role.as_deref() {
        return exec_tmux_role(&cfg, args);
    }

    let Some(command) = cli.command else {
        return Err(NiriCtxError::Config(
            "usage: niri-ctx <open|scratch|comms|spotify|top-ambient|devtools-here|startup|watch|doctor|current|inspect|plan|init-config>".to_string(),
        ));
    };

    match command {
        Command::Watch => commands::watch::run(&cfg).map(|()| 0),
        Command::Doctor { json } => {
            commands::doctor::run(&cfg, cli.json || json).map(|code| code as u8)
        }
        Command::InitConfig => {
            let path = cfg.write_frozen_toml()?;
            println!("{}", path.display());
            Ok(0)
        }
        Command::Current => {
            let state = snapshot_state(&cfg)?;
            commands::current::print_current(&cfg, &state)?;
            Ok(0)
        }
        Command::Inspect { json } => {
            let state = snapshot_state(&cfg)?;
            commands::inspect::print(&cfg, &state, cli.json || json)?;
            Ok(0)
        }
        Command::Plan { command } => {
            let nested = commands::parse_plan_command(&command)?;
            let state = snapshot_state(&cfg)?;
            let Some(goal) = goal_from_command(&nested)? else {
                return Err(NiriCtxError::Config(
                    "plan only supports planner commands".to_string(),
                ));
            };
            let effects = plan(&cfg, &state, &goal)?;
            commands::plan::print(&effects, cli.json)?;
            Ok(0)
        }
        other => {
            let Some(goal) = goal_from_command(&other)? else {
                return Err(NiriCtxError::Config("unsupported command".to_string()));
            };
            if cli.dry_run {
                let state = snapshot_state(&cfg)?;
                let effects = plan(&cfg, &state, &goal)?;
                commands::plan::print(&effects, cli.json)?;
                return Ok(0);
            }
            if requires_lock(&other) {
                match GlobalLock::try_acquire()? {
                    LockAttempt::Acquired(_guard) => {
                        run_mutating_loop(&cfg, &goal, command_name(&other))?
                    }
                    LockAttempt::Busy => run_focus_only_recovery(&cfg, &goal)?,
                }
            } else if matches!(other, Command::Startup) {
                run_startup(&cfg)?;
            } else {
                run_mutating_loop(&cfg, &goal, command_name(&other))?;
            }
            Ok(0)
        }
    }
}

fn snapshot_state(cfg: &Config) -> Result<DesktopState> {
    let mut client = IpcNiriClient::new();
    snapshot_state_with_client(cfg, &mut client)
}

fn snapshot_state_with_client(cfg: &Config, client: &mut dyn NiriClient) -> Result<DesktopState> {
    let mut state = DesktopState::snapshot(client)?;
    state.load_browser_cache(cfg)?;
    Ok(state)
}

fn run_mutating_loop(cfg: &Config, goal: &Goal, command: &str) -> Result<()> {
    let mut client = IpcNiriClient::new();
    let mut launcher = ProcessLauncher;
    let mut sessions = RealSessionBackend::from_config(cfg);
    // Resolve `current` ONCE, like Bash did before locking: focus can move
    // between convergence iterations (focus-follows-mouse, spawned windows)
    // and the command must not retarget to a different context mid-run.
    let goal = match goal {
        Goal::Open {
            ctx: crate::model::ContextArg::Current,
            role,
        } => {
            let state = snapshot_state_with_client(cfg, &mut client)?;
            let ctx = crate::planner::resolve_context_arg(
                cfg,
                &state,
                crate::model::ContextArg::Current,
            )?;
            Goal::Open {
                ctx: crate::model::ContextArg::Context(ctx),
                role: role.clone(),
            }
        }
        other => other.clone(),
    };
    converge_loop(
        cfg,
        &goal,
        command,
        &mut client,
        &mut launcher,
        &mut sessions,
    )
    .map(|_| ())
}

pub fn converge_loop(
    cfg: &Config,
    goal: &Goal,
    command: &str,
    client: &mut dyn NiriClient,
    launcher: &mut dyn launcher::Launcher,
    sessions: &mut dyn SessionBackend,
) -> Result<usize> {
    let mut remaining = Vec::new();
    for iteration in 1..=cfg.behavior.converge_iters {
        let state = snapshot_state_with_client(cfg, client)?;
        maybe_deep_link(cfg, &state, goal, sessions)?;
        let effects = plan(cfg, &state, goal)?;
        if effects.is_empty() {
            return Ok(if iteration == 1 { 1 } else { iteration - 1 });
        }
        remaining = effects.clone();
        Executor::new(cfg, ExecutorMode::Live, client, launcher, sessions).run(&effects)?;
    }
    // Height equalization is best-effort: an app's min-height constraint can
    // make exactly-equal tiles unreachable. Don't fail the whole command over
    // residue that is only SetWindowHeight.
    if remaining
        .iter()
        .all(|effect| matches!(effect, Effect::SetWindowHeight { .. }))
    {
        tracing::warn!(
            ?remaining,
            "converged with best-effort height residue (app size constraints?)"
        );
        return Ok(cfg.behavior.converge_iters);
    }
    Err(NiriCtxError::NoConverge {
        command: command.to_string(),
        iterations: cfg.behavior.converge_iters,
        remaining_effects: remaining,
    })
}

fn run_focus_only_recovery(cfg: &Config, goal: &Goal) -> Result<()> {
    // Bash returns immediately for lock-busy devtools-here — moving the
    // focused window is exactly what a concurrent dispatcher must not race.
    if matches!(goal, Goal::DevtoolsHere) {
        tracing::info!("lock busy; devtools-here is a no-op");
        return Ok(());
    }
    tracing::info!(?goal, "lock busy; running focus-only recovery");
    let mut client = IpcNiriClient::new();
    let mut launcher = ProcessLauncher;
    let mut sessions = NoopSessionBackend;
    let state = snapshot_state_with_client(cfg, &mut client)?;
    let effects = plan(cfg, &state, goal)?;
    let focus_effects = focus_only(&effects);
    Executor::new(
        cfg,
        ExecutorMode::Live,
        &mut client,
        &mut launcher,
        &mut sessions,
    )
    .run(&focus_effects)
}

fn run_startup(cfg: &Config) -> Result<()> {
    let mut client = IpcNiriClient::new();
    let found = (0..75).any(|_| {
        let ready = client.workspaces().map(|workspaces| {
            workspaces.iter().any(|workspace| {
                workspace.output == cfg.outputs.main
                    && workspace.name.as_deref().is_some_and(|name| name == "UP")
            })
        });
        match ready {
            Ok(true) => true,
            Ok(false) | Err(_) => {
                thread::sleep(Duration::from_millis(200));
                false
            }
        }
    });
    if !found {
        tracing::info!("startup timed out waiting for UP on main output");
        return Ok(());
    }
    let mut launcher = ProcessLauncher;
    let mut sessions = NoopSessionBackend;
    converge_loop(
        cfg,
        &Goal::Startup,
        "startup",
        &mut client,
        &mut launcher,
        &mut sessions,
    )
    .map(|_| ())
}

fn maybe_deep_link(
    cfg: &Config,
    state: &DesktopState,
    goal: &Goal,
    sessions: &mut dyn SessionBackend,
) -> Result<()> {
    let Goal::Open { ctx, role } = goal else {
        return Ok(());
    };
    let ctx = resolve_context_arg(cfg, state, *ctx)?;
    let role = if *role == Role::All {
        cfg.terminal_role_for_open_all(ctx)
    } else {
        role.clone()
    };
    if matches!(role, Role::Docs | Role::Output) {
        return Ok(());
    }
    let app_id = cfg.work_app_id(ctx)?;
    if state.oldest_window_by_app_id(&app_id).is_some() {
        sessions.ensure_and_deep_link(cfg, ctx, &role)?;
    }
    Ok(())
}

fn requires_lock(command: &Command) -> bool {
    matches!(
        command,
        Command::Open { .. }
            | Command::Scratch
            | Command::Comms
            | Command::Spotify
            | Command::DevtoolsHere
    )
}

fn command_name(command: &Command) -> &'static str {
    match command {
        Command::Open { .. } => "open",
        Command::Scratch => "scratch",
        Command::Comms => "comms",
        Command::Spotify => "spotify",
        Command::TopAmbient => "top-ambient",
        Command::DevtoolsHere => "devtools-here",
        Command::Startup => "startup",
        Command::Watch => "watch",
        Command::Doctor { .. } => "doctor",
        Command::Current => "current",
        Command::Inspect { .. } => "inspect",
        Command::Plan { .. } => "plan",
        Command::InitConfig => "init-config",
    }
}

fn exec_tmux_role(cfg: &Config, args: &[String]) -> Result<u8> {
    if args.len() != 2 {
        return Err(NiriCtxError::Config(
            "--tmux-role requires <ctx> <role>".to_string(),
        ));
    }
    let err = ProcessCommand::new("bash")
        .arg(&cfg.behavior.bash_fallback)
        .arg("--tmux-role")
        .arg(&args[0])
        .arg(&args[1])
        .exec();
    Err(NiriCtxError::io(&cfg.behavior.bash_fallback, err))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::ExitStatus;
    use std::sync::Mutex;

    use std::os::unix::process::ExitStatusExt;

    use crate::config::Config;
    use crate::launcher::{LaunchedProcess, Launcher};
    use crate::model::{BrowserRole, Context, ContextArg, WindowId, WorkspaceId};
    use crate::niri::fake::FakeNiriClient;
    use crate::niri::{NiriAction, Window, Workspace};
    use crate::session::FakeSessionBackend;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[derive(Debug, Default)]
    struct FakeLauncher {
        spawns: Vec<String>,
        kills: Vec<String>,
        status: Option<ExitStatus>,
    }

    impl Launcher for FakeLauncher {
        fn spawn_terminal(
            &mut self,
            _cfg: &Config,
            _ctx: Context,
            _role: &Role,
            app_id: &str,
            _title: &str,
        ) -> Result<LaunchedProcess> {
            self.spawns.push(format!("terminal:{app_id}"));
            Ok(LaunchedProcess::fake(
                vec!["terminal".to_string()],
                app_id.to_string(),
                self.status,
            ))
        }

        fn spawn_browser(
            &mut self,
            _cfg: &Config,
            _ctx: Context,
            role: BrowserRole,
            _profile: &str,
        ) -> Result<LaunchedProcess> {
            self.spawns.push(format!("browser:{}", role.as_str()));
            Ok(LaunchedProcess::fake(
                vec!["helium".to_string()],
                "helium".to_string(),
                self.status,
            ))
        }

        fn spawn_comms_app(&mut self, cfg: &Config, app: &str) -> Result<Option<LaunchedProcess>> {
            let Some(app_cfg) = cfg
                .comms
                .apps
                .iter()
                .find(|candidate| candidate.name == app)
            else {
                return Ok(None);
            };
            self.spawns.push(format!("comms:{app}"));
            Ok(Some(LaunchedProcess::fake(
                vec![app.to_string()],
                app_cfg.app_id.clone(),
                self.status,
            )))
        }

        fn spawn_spotify(&mut self, cfg: &Config) -> Result<LaunchedProcess> {
            self.spawns.push("spotify".to_string());
            Ok(LaunchedProcess::fake(
                vec!["spotify".to_string()],
                cfg.ambient.spotify_app_id.clone(),
                self.status,
            ))
        }

        fn kill_class_marked(&mut self, app_id: &str) -> Result<()> {
            self.kills.push(app_id.to_string());
            Ok(())
        }
    }

    fn cfg() -> Config {
        Config::default_for_repo("/repo")
    }

    fn ws(id: u64, name: &str, output: &str, active: bool, focused: bool) -> Workspace {
        Workspace {
            id: WorkspaceId(id),
            name: Some(name.to_string()),
            output: output.to_string(),
            is_active: active,
            is_focused: focused,
        }
    }

    fn win(
        id: u64,
        app_id: &str,
        ws: u64,
        focused: bool,
        column: Option<(usize, usize)>,
    ) -> Window {
        Window {
            id: WindowId(id),
            title: String::new(),
            app_id: app_id.to_string(),
            pid: id as u32,
            workspace_id: WorkspaceId(ws),
            is_focused: focused,
            is_floating: false,
            column,
            tile_height: Some(500.0),
        }
    }

    fn base_workspaces() -> Vec<Workspace> {
        vec![
            ws(1, "UP", "DP-1", false, false),
            ws(2, "Webroot", "DP-1", true, true),
            ws(3, "Side", "DP-1", false, false),
            ws(4, "Admin", "DP-1", false, false),
            ws(5, "comms", "HDMI-A-1", true, false),
            ws(6, "top-ambient", "DP-2", true, false),
            ws(7, "scratch", "DP-1", false, false),
        ]
    }

    fn set_cache_dir(temp: &tempfile::TempDir) {
        std::env::set_var("XDG_CACHE_HOME", temp.path());
        std::env::set_var("NIRI_SOCKET", "test-niri-socket");
    }

    fn write_cache(temp: &tempfile::TempDir, slug: &str, role: BrowserRole, id: u64) {
        let dir = temp.path().join("niri-ctx");
        std::fs::create_dir_all(&dir).expect("cache dir");
        std::fs::write(
            dir.join(format!("browser-{}-{}.id", slug, role.as_str())),
            format!("{id}\ntest-niri-socket\n"),
        )
        .expect("cache write");
    }

    #[test]
    fn open_up_from_empty_converges_in_two_mutating_passes() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        let cfg = cfg();
        let mut client = FakeNiriClient::new(base_workspaces(), vec![]);
        let mut launcher = FakeLauncher::default();
        let mut sessions = FakeSessionBackend::default();
        let goal = Goal::Open {
            ctx: ContextArg::Context(Context::UP),
            role: Role::All,
        };

        let iterations = converge_loop(
            &cfg,
            &goal,
            "open",
            &mut client,
            &mut launcher,
            &mut sessions,
        )
        .expect("converged");

        assert!(iterations <= 2, "iterations={iterations}");
        assert!(client
            .windows
            .iter()
            .any(|window| window.app_id == "helium" && window.workspace_id == WorkspaceId(1)));
        assert!(client.windows.iter().any(|window| {
            window.app_id == "dev.yiannis.niri.up.work" && window.workspace_id == WorkspaceId(1)
        }));
    }

    #[test]
    fn settled_open_up_converges_in_one_empty_plan_iteration() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        write_cache(&temp, "up", BrowserRole::Docs, 10);
        let cfg = cfg();
        let mut workspaces = base_workspaces();
        workspaces[0].is_active = true;
        workspaces[0].is_focused = true;
        workspaces[1].is_active = false;
        workspaces[1].is_focused = false;
        let mut client = FakeNiriClient::new(
            workspaces,
            vec![
                win(10, "helium", 1, true, Some((1, 1))),
                win(11, "dev.yiannis.niri.up.work", 1, false, Some((2, 1))),
            ],
        );
        let mut launcher = FakeLauncher::default();
        let mut sessions = FakeSessionBackend::default();
        let goal = Goal::Open {
            ctx: ContextArg::Context(Context::UP),
            role: Role::All,
        };

        let iterations = converge_loop(
            &cfg,
            &goal,
            "open",
            &mut client,
            &mut launcher,
            &mut sessions,
        )
        .expect("converged");

        assert_eq!(iterations, 1);
        assert!(launcher.spawns.is_empty());
    }

    #[test]
    fn comms_from_scattered_state_converges_to_one_column() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        let cfg = cfg();
        let mut client = FakeNiriClient::new(
            base_workspaces(),
            vec![
                win(20, "slack", 1, false, Some((1, 1))),
                win(21, "org.telegram.desktop", 2, false, Some((1, 1))),
                win(22, "discord", 3, false, Some((1, 1))),
            ],
        );
        let mut launcher = FakeLauncher::default();
        let mut sessions = FakeSessionBackend::default();

        converge_loop(
            &cfg,
            &Goal::Comms,
            "comms",
            &mut client,
            &mut launcher,
            &mut sessions,
        )
        .expect("converged");

        let cols = client
            .windows
            .iter()
            .filter(|window| window.workspace_id == WorkspaceId(5))
            .filter_map(|window| window.column.map(|(column, _)| column))
            .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(cols.len(), 1);
    }

    #[test]
    fn spawn_never_maps_reports_alive_and_exited_states_after_retry() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        let cfg = cfg();
        // The kill+retry self-heal is TERMINAL-only; use the work-card role.
        let goal = Goal::Open {
            ctx: ContextArg::Context(Context::UP),
            role: Role::Editor,
        };

        let mut alive_client = FakeNiriClient::new(base_workspaces(), vec![]);
        alive_client.map_spawns = false;
        alive_client.wait_never_maps = true;
        let mut alive_launcher = FakeLauncher::default();
        let mut sessions = FakeSessionBackend::default();
        let err = converge_loop(
            &cfg,
            &goal,
            "open",
            &mut alive_client,
            &mut alive_launcher,
            &mut sessions,
        )
        .expect_err("alive launch should fail");
        assert!(err.to_string().contains("alive"));
        assert_eq!(alive_launcher.spawns.len(), 2);

        let mut exited_client = FakeNiriClient::new(base_workspaces(), vec![]);
        exited_client.map_spawns = false;
        exited_client.wait_never_maps = true;
        let mut exited_launcher = FakeLauncher {
            status: Some(ExitStatus::from_raw(7 << 8)),
            ..FakeLauncher::default()
        };
        let err = converge_loop(
            &cfg,
            &goal,
            "open",
            &mut exited_client,
            &mut exited_launcher,
            &mut sessions,
        )
        .expect_err("exited launch should fail");
        assert!(err.to_string().contains("process exited with code 7"));
    }

    #[test]
    fn browser_spawn_never_maps_fails_without_retry() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        let cfg = cfg();
        let goal = Goal::Open {
            ctx: ContextArg::Context(Context::UP),
            role: Role::Docs,
        };
        let mut client = FakeNiriClient::new(base_workspaces(), vec![]);
        client.map_spawns = false;
        client.wait_never_maps = true;
        let mut launcher = FakeLauncher::default();
        let mut sessions = FakeSessionBackend::default();
        let err = converge_loop(
            &cfg,
            &goal,
            "open",
            &mut client,
            &mut launcher,
            &mut sessions,
        )
        .expect_err("browser launch should fail");
        assert!(err.to_string().contains("never appeared"), "{err}");
        // No kill-by-class + respawn for browsers: a late-mapping first
        // instance must not be duplicated.
        assert_eq!(launcher.spawns.len(), 1);
        assert!(launcher.kills.is_empty());
    }

    #[test]
    fn lock_contention_executes_focus_only_effects() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        write_cache(&temp, "up", BrowserRole::Docs, 10);
        let cfg = cfg();
        let state = DesktopState::new(
            base_workspaces(),
            vec![win(10, "helium", 2, false, Some((1, 1)))],
        );
        let mut state = state;
        state.load_browser_cache(&cfg).expect("cache");
        let effects = plan(
            &cfg,
            &state,
            &Goal::Open {
                ctx: ContextArg::Context(Context::UP),
                role: Role::Docs,
            },
        )
        .expect("plan");
        let focus = focus_only(&effects);
        assert!(focus.iter().all(|effect| matches!(
            effect,
            crate::planner::Effect::FocusOutput { .. }
                | crate::planner::Effect::FocusWorkspace { .. }
                | crate::planner::Effect::FocusWindow { .. }
        )));

        let mut client = FakeNiriClient::new(
            base_workspaces(),
            vec![win(10, "helium", 2, false, Some((1, 1)))],
        );
        let mut launcher = FakeLauncher::default();
        let mut sessions = FakeSessionBackend::default();
        Executor::new(
            &cfg,
            ExecutorMode::Live,
            &mut client,
            &mut launcher,
            &mut sessions,
        )
        .run(&focus)
        .expect("focus only");
        assert!(client.actions.iter().all(|action| matches!(
            action,
            NiriAction::FocusOutput { .. }
                | NiriAction::FocusWorkspace { .. }
                | NiriAction::FocusWindow { .. }
        )));
    }

    #[test]
    fn fake_session_backend_deep_links_existing_work_card() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        let cfg = cfg();
        let state = DesktopState::new(
            base_workspaces(),
            vec![win(11, "dev.yiannis.niri.up.work", 1, true, Some((2, 1)))],
        );
        let mut sessions = FakeSessionBackend::default();
        sessions
            .workspaces
            .insert("editor".to_string(), vec!["1".to_string()]);
        maybe_deep_link(
            &cfg,
            &state,
            &Goal::Open {
                ctx: ContextArg::Context(Context::UP),
                role: Role::Agents,
            },
            &mut sessions,
        )
        .expect("deep link");
        assert_eq!(
            sessions.calls,
            vec![
                "ensure:UP-work:agents",
                "rename-workspace:editor:mono",
                "rename-tab:mono:1:editor",
                "create-tab:mono:agents",
                "create-tab:mono:logs",
                "focus-tab:mono:agents"
            ]
        );
        assert_eq!(
            sessions.workspaces.get("mono"),
            Some(&vec![
                "editor".to_string(),
                "agents".to_string(),
                "logs".to_string()
            ])
        );

        sessions.calls.clear();
        sessions
            .ensure_and_deep_link(&cfg, Context::Admin, &Role::Term)
            .expect("admin session");
        assert_eq!(
            sessions.calls,
            vec!["ensure:Admin-work:term", "admin-focus:term"]
        );
        assert_eq!(sessions.focused_workspace.as_deref(), Some("term"));
    }

    #[test]
    fn drifted_cards_action_ordering_is_stable() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|err| err.into_inner());
        let temp = tempfile::tempdir().expect("tempdir");
        set_cache_dir(&temp);
        let cfg = cfg();
        let state = DesktopState::new(
            base_workspaces(),
            vec![
                win(10, "helium", 2, false, Some((3, 1))),
                win(11, "dev.yiannis.niri.up.work", 3, false, Some((1, 1))),
            ],
        )
        .with_browser_cache_entry("up", BrowserRole::Docs, WindowId(10));
        let effects = plan(
            &cfg,
            &state,
            &Goal::Open {
                ctx: ContextArg::Context(Context::UP),
                role: Role::All,
            },
        )
        .expect("plan");
        let names = effects
            .iter()
            .map(|effect| match effect {
                crate::planner::Effect::FocusOutput { .. } => "focus-output",
                crate::planner::Effect::FocusWorkspace { .. } => "focus-workspace",
                crate::planner::Effect::MoveWindowToWorkspace { .. } => "move-window",
                crate::planner::Effect::FocusWindow { .. } => "focus-window",
                crate::planner::Effect::MoveColumnToIndex { .. } => "move-column",
                other => panic!("unexpected effect in drifted plan: {other:?}"),
            })
            .collect::<Vec<_>>();
        assert_eq!(
            names,
            vec![
                "focus-workspace",
                "move-window",
                "move-window",
                "focus-window",
                "move-column",
                "focus-window",
                "move-column",
                "focus-workspace",
                "focus-window"
            ]
        );
    }
}
