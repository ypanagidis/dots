use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

use crate::config::{repo_root, Config};
use crate::error::Result;
use crate::niri::ipc::IpcNiriClient;
use crate::niri::NiriClient;

#[derive(Debug, serde::Serialize)]
pub struct Check {
    pub name: String,
    pub status: Status,
    pub message: String,
}

#[derive(Debug, serde::Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Ok,
    Warn,
    Fail,
}

pub fn run(cfg: &Config, json: bool) -> Result<i32> {
    let mut checks = vec![
        check_binary("niri"),
        check_niri_validate(),
        check_niri_socket(),
        check_binary("jq"),
        check_binary("tmux"),
        check_binary(&cfg.terminal.program),
        check_helium(cfg),
        check_spotify(cfg),
        check_bash_fallback(cfg),
        check_config(cfg),
        check_herdr(cfg),
        check_herdr_symlink(),
        check_systemd_watch(),
        check_legacy_cache(),
        check_installed_path_and_keybinds(),
    ];
    checks.extend(check_outputs(cfg));
    checks.push(check_version());

    let exit = if checks.iter().any(|check| check.status == Status::Fail) {
        1
    } else {
        0
    };
    if json {
        println!("{}", serde_json::to_string_pretty(&checks)?);
    } else {
        for check in &checks {
            println!("{:?}: {} - {}", check.status, check.name, check.message);
        }
    }
    Ok(exit)
}

fn check_binary(name: &str) -> Check {
    if command_exists(name) {
        ok(name, "found")
    } else {
        fail(name, "not found on PATH")
    }
}

fn check_niri_validate() -> Check {
    let config = repo_root().join(".config/niri/config.kdl");
    if !command_exists("niri") {
        return fail("niri validate", "niri not found");
    }
    match Command::new("niri")
        .arg("validate")
        .arg("-c")
        .arg(&config)
        .output()
    {
        Ok(output) if output.status.success() => ok("niri validate", "config validates"),
        Ok(output) => fail(
            "niri validate",
            String::from_utf8_lossy(&output.stderr).as_ref(),
        ),
        Err(err) => fail("niri validate", &err.to_string()),
    }
}

fn check_niri_socket() -> Check {
    if std::env::var_os("NIRI_SOCKET").is_none() {
        return fail("NIRI_SOCKET", "not set");
    }
    let mut client = IpcNiriClient::new();
    match client.workspaces() {
        Ok(_) => ok("niri workspaces", "reachable"),
        Err(err) => fail("niri workspaces", &err.to_string()),
    }
}

fn check_outputs(cfg: &Config) -> Vec<Check> {
    let mut client = IpcNiriClient::new();
    let workspaces = match client.workspaces() {
        Ok(workspaces) => workspaces,
        Err(err) => return vec![fail("outputs", &err.to_string())],
    };
    [
        ("MAIN_OUTPUT", cfg.outputs.main.as_str(), true),
        ("TOP_OUTPUT", cfg.outputs.top.as_str(), false),
        ("COMMS_OUTPUT", cfg.outputs.vertical.as_str(), false),
    ]
    .into_iter()
    .map(|(label, output, required)| {
        if workspaces
            .iter()
            .any(|workspace| workspace.output == output)
        {
            ok(label, output)
        } else if required {
            fail(label, output)
        } else {
            warn(label, output)
        }
    })
    .collect()
}

fn check_helium(cfg: &Config) -> Check {
    if executable(&cfg.browser.bin) || command_exists("helium") {
        ok("helium", "found")
    } else {
        fail("helium", "not found")
    }
}

fn check_spotify(cfg: &Config) -> Check {
    let found = cfg
        .ambient
        .spotify_launch
        .iter()
        .filter_map(|argv| argv.first())
        .any(|bin| command_exists(bin));
    if found {
        ok("spotify", "launcher found")
    } else {
        warn("spotify", "no launcher found")
    }
}

fn check_bash_fallback(cfg: &Config) -> Check {
    if executable(&cfg.behavior.bash_fallback) {
        ok(
            "bash_fallback",
            &cfg.behavior.bash_fallback.display().to_string(),
        )
    } else {
        fail(
            "bash_fallback",
            &cfg.behavior.bash_fallback.display().to_string(),
        )
    }
}

fn check_config(cfg: &Config) -> Check {
    match cfg.validate() {
        Ok(warnings) if warnings.is_empty() => ok("config", "valid"),
        Ok(warnings) => warn("config", &warnings.join("; ")),
        Err(err) => fail("config", &err.to_string()),
    }
}

fn check_herdr(cfg: &Config) -> Check {
    if cfg.behavior.session_backend != "herdr" {
        return ok("herdr", "not selected");
    }
    if command_exists("herdr") {
        ok("herdr", "found")
    } else {
        fail("herdr", "SESSION_BACKEND=herdr but herdr not found")
    }
}

fn check_herdr_symlink() -> Check {
    let Some(home) = std::env::var_os("HOME") else {
        return warn("herdr config", "HOME not set");
    };
    let path = Path::new(&home).join(".config/herdr/config.toml");
    match fs::read_link(&path) {
        Ok(target) if target == repo_root().join(".config/herdr/config.toml") => {
            ok("herdr config", "symlink ok")
        }
        Ok(target) => warn("herdr config", &format!("points to {}", target.display())),
        Err(err) => warn("herdr config", &err.to_string()),
    }
}

fn check_systemd_watch() -> Check {
    match Command::new("systemctl")
        .args(["--user", "is-active", "niri-ctx-watch"])
        .output()
    {
        Ok(output) if output.status.success() => ok("niri-ctx-watch", "active"),
        Ok(output) => warn(
            "niri-ctx-watch",
            String::from_utf8_lossy(&output.stdout).trim(),
        ),
        Err(err) => warn("niri-ctx-watch", &err.to_string()),
    }
}

fn check_legacy_cache() -> Check {
    let Some(home) = std::env::var_os("HOME") else {
        return warn("legacy cache", "HOME not set");
    };
    let cache = Path::new(&home).join(".cache");
    let found = fs::read_dir(cache)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(std::result::Result::ok)
        .any(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("niri-browser-")
        });
    if found {
        warn("legacy cache", "legacy niri-browser-* files exist")
    } else {
        ok("legacy cache", "none")
    }
}

fn check_installed_path_and_keybinds() -> Check {
    let Some(home) = std::env::var_os("HOME") else {
        return warn("installed niri-ctx", "HOME not set");
    };
    let installed = Path::new(&home).join(".local/bin/niri-ctx");
    let keybinds = repo_root().join(".config/niri/cfg/keybinds.kdl");
    let keybinds_ok = fs::read_to_string(&keybinds)
        .map(|text| text.contains("niri-ctx"))
        .unwrap_or(false);
    if installed.exists() && keybinds_ok {
        ok("installed niri-ctx", "path and keybinds present")
    } else {
        fail("installed niri-ctx", "missing path or keybind mention")
    }
}

fn check_version() -> Check {
    let mut client = IpcNiriClient::new();
    match client.version() {
        Ok(version) => ok("niri version", &version),
        Err(err) => warn("niri version", &err.to_string()),
    }
}

fn command_exists(name: &str) -> bool {
    if name.contains('/') {
        return executable(Path::new(name));
    }
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|dir| executable(&dir.join(name)))
}

fn executable(path: &Path) -> bool {
    path.metadata()
        .map(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn ok(name: &str, message: &str) -> Check {
    check(name, Status::Ok, message)
}

fn warn(name: &str, message: &str) -> Check {
    check(name, Status::Warn, message)
}

fn fail(name: &str, message: &str) -> Check {
    check(name, Status::Fail, message)
}

fn check(name: &str, status: Status, message: &str) -> Check {
    Check {
        name: name.to_string(),
        status,
        message: message.to_string(),
    }
}
