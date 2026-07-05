mod cli;
mod commands;
mod config;
mod error;
mod executor;
mod launcher;
mod logging;
mod matchers;
mod model;
mod niri;
mod planner;
mod session;
mod state;

use std::os::unix::process::CommandExt;
use std::process::{Command as ProcessCommand, ExitCode};

use clap::Parser;

use crate::cli::{Cli, Command};
use crate::commands::goal_from_command;
use crate::config::Config;
use crate::error::{NiriCtxError, Result};
use crate::executor::{Executor, ExecutorMode};
use crate::niri::ipc::IpcNiriClient;
use crate::planner::plan;
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
        Command::Watch => commands::watch::run().map(|()| 0),
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
            let state = snapshot_state(&cfg)?;
            let Some(goal) = goal_from_command(&other)? else {
                return Err(NiriCtxError::Config("unsupported command".to_string()));
            };
            let effects = plan(&cfg, &state, &goal)?;
            let mode = if cli.dry_run {
                ExecutorMode::DryRun
            } else {
                ExecutorMode::Phase1Live
            };
            Executor::new(mode).run(&effects)?;
            Ok(0)
        }
    }
}

fn snapshot_state(cfg: &Config) -> Result<DesktopState> {
    let mut client = IpcNiriClient::new();
    let mut state = DesktopState::snapshot(&mut client)?;
    state.load_browser_cache(cfg)?;
    Ok(state)
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
