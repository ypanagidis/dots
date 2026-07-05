pub mod comms;
pub mod current;
pub mod devtools;
pub mod doctor;
pub mod inspect;
pub mod open;
pub mod plan;
pub mod startup;
pub mod top_ambient;
pub mod watch;

use clap::Parser;

use crate::cli::{Cli, Command};
use crate::error::{NiriCtxError, Result};
use crate::model::{ContextArg, Role};
use crate::planner::Goal;

pub fn goal_from_command(command: &Command) -> Result<Option<Goal>> {
    match command {
        Command::Open { ctx, role } => Ok(Some(Goal::Open {
            ctx: ctx.parse::<ContextArg>()?,
            role: Role::parse(role.as_deref())?,
        })),
        Command::Scratch => Ok(Some(Goal::Scratch)),
        Command::Comms => Ok(Some(Goal::Comms)),
        Command::Spotify => Ok(Some(Goal::Spotify)),
        Command::TopAmbient => Ok(Some(Goal::TopAmbient)),
        Command::DevtoolsHere => Ok(Some(Goal::DevtoolsHere)),
        Command::Startup => Ok(Some(Goal::Startup)),
        Command::Current => Ok(Some(Goal::Current)),
        Command::Watch
        | Command::Doctor { .. }
        | Command::Inspect { .. }
        | Command::Plan { .. }
        | Command::InitConfig => Ok(None),
    }
}

pub fn parse_plan_command(args: &[String]) -> Result<Command> {
    let argv = std::iter::once("niri-ctx".to_string())
        .chain(args.iter().cloned())
        .collect::<Vec<_>>();
    let cli = Cli::try_parse_from(argv).map_err(|err| NiriCtxError::Config(err.to_string()))?;
    cli.command
        .ok_or_else(|| NiriCtxError::Config("plan requires a command".to_string()))
}
