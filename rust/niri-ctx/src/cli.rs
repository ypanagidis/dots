use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "niri-ctx")]
#[command(about = "Context dispatcher for niri", disable_help_subcommand = true)]
pub struct Cli {
    #[arg(long, global = true)]
    pub dry_run: bool,
    #[arg(long, global = true)]
    pub json: bool,
    #[arg(long, global = true)]
    pub verbose: bool,
    #[arg(long = "tmux-role", value_names = ["CTX", "ROLE"], num_args = 2)]
    pub tmux_role: Option<Vec<String>>,
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Debug, Clone, Subcommand)]
pub enum Command {
    Open {
        ctx: String,
        role: Option<String>,
    },
    Scratch,
    Comms,
    Spotify,
    #[command(name = "top-ambient")]
    TopAmbient,
    #[command(name = "devtools-here")]
    DevtoolsHere,
    Startup,
    Watch,
    Doctor {
        #[arg(long)]
        json: bool,
    },
    Current,
    Inspect {
        #[arg(long)]
        json: bool,
    },
    Plan {
        #[arg(trailing_var_arg = true, required = true)]
        command: Vec<String>,
    },
    #[command(name = "init-config")]
    InitConfig,
}
