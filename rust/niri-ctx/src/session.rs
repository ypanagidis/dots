use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use crate::config::{Config, ContextConfig, RepoConfig};
use crate::error::{NiriCtxError, Result};
use crate::model::{Context, Role};

pub trait SessionBackend {
    fn session_exists(&mut self, session: &str) -> Result<bool>;
    fn reap_fresh_session(&mut self, session: &str) -> Result<()>;
    fn deep_link(&mut self, cfg: &Config, ctx: Context, role: &Role) -> Result<()>;
}

pub struct NoopSessionBackend;

impl SessionBackend for NoopSessionBackend {
    fn session_exists(&mut self, _session: &str) -> Result<bool> {
        Ok(false)
    }

    fn reap_fresh_session(&mut self, _session: &str) -> Result<()> {
        Ok(())
    }

    fn deep_link(&mut self, _cfg: &Config, _ctx: Context, _role: &Role) -> Result<()> {
        Ok(())
    }
}

pub enum RealSessionBackend {
    Herdr(HerdrBackend),
    Tmux(TmuxBackend),
}

impl RealSessionBackend {
    pub fn from_config(cfg: &Config) -> Self {
        if cfg.behavior.session_backend == "tmux" {
            Self::Tmux(TmuxBackend)
        } else {
            Self::Herdr(HerdrBackend)
        }
    }
}

impl SessionBackend for RealSessionBackend {
    fn session_exists(&mut self, session: &str) -> Result<bool> {
        match self {
            Self::Herdr(backend) => backend.session_exists(session),
            Self::Tmux(backend) => backend.session_exists(session),
        }
    }

    fn reap_fresh_session(&mut self, session: &str) -> Result<()> {
        match self {
            Self::Herdr(backend) => backend.reap_fresh_session(session),
            Self::Tmux(backend) => backend.reap_fresh_session(session),
        }
    }

    fn deep_link(&mut self, cfg: &Config, ctx: Context, role: &Role) -> Result<()> {
        match self {
            Self::Herdr(backend) => backend.deep_link(cfg, ctx, role),
            Self::Tmux(backend) => backend.deep_link(cfg, ctx, role),
        }
    }
}

pub struct HerdrBackend;

impl SessionBackend for HerdrBackend {
    fn session_exists(&mut self, session: &str) -> Result<bool> {
        if !valid_session_name(session) || which("herdr").is_none() {
            return Ok(false);
        }
        let output = Command::new("herdr")
            .args(["session", "list", "--json"])
            .stdin(Stdio::null())
            .output()
            .map_err(|source| NiriCtxError::io("herdr session list", source))?;
        if !output.status.success() {
            return Ok(false);
        }
        let value: serde_json::Value = serde_json::from_slice(&output.stdout)?;
        Ok(value
            .get("sessions")
            .and_then(serde_json::Value::as_array)
            .is_some_and(|sessions| {
                sessions.iter().any(|item| {
                    item.get("name").and_then(serde_json::Value::as_str) == Some(session)
                })
            }))
    }

    fn reap_fresh_session(&mut self, session: &str) -> Result<()> {
        if !valid_session_name(session) || which("herdr").is_none() {
            return Ok(());
        }
        tracing::info!(session, "reaping fresh herdr session after spawn timeout");
        let _ = run_timeout(
            Command::new("herdr").args(["session", "stop", session]),
            Duration::from_secs(3),
        );
        let _ = run_timeout(
            Command::new("herdr").args(["session", "delete", session]),
            Duration::from_secs(3),
        );
        Ok(())
    }

    fn deep_link(&mut self, cfg: &Config, ctx: Context, role: &Role) -> Result<()> {
        if *role == Role::All {
            return Ok(());
        }
        let session = role_session_name(ctx, role)?;
        if which("herdr").is_none() {
            return if TmuxBackend.session_exists(&session)? {
                TmuxBackend.deep_link(cfg, ctx, role)
            } else {
                Ok(())
            };
        }
        if !herdr_sock_for_session(&session)?.is_socket() && TmuxBackend.session_exists(&session)? {
            return TmuxBackend.deep_link(cfg, ctx, role);
        }
        focus_role_target(cfg, ctx, role, &session)
    }
}

pub struct TmuxBackend;

impl SessionBackend for TmuxBackend {
    fn session_exists(&mut self, session: &str) -> Result<bool> {
        Ok(Command::new("tmux")
            .args(["has-session", "-t", session])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false))
    }

    fn reap_fresh_session(&mut self, _session: &str) -> Result<()> {
        Ok(())
    }

    fn deep_link(&mut self, cfg: &Config, ctx: Context, role: &Role) -> Result<()> {
        if which("tmux").is_none() || *role == Role::All {
            return Ok(());
        }
        let session = role_session_name(ctx, role)?;
        ensure_tmux_target(cfg, ctx, role, &session)?;
        let window = tmux_target_window(cfg, ctx, role, &session)?;
        let _ = Command::new("tmux")
            .args(["select-window", "-t", &format!("{session}:{window}")])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        Ok(())
    }
}

pub fn role_session_name(ctx: Context, role: &Role) -> Result<String> {
    match role {
        Role::Editor | Role::Agents | Role::Logs | Role::Term | Role::Repo(_) | Role::All => {
            Ok(format!("{}-work", ctx.name()))
        }
        Role::Docs | Role::Output => Err(NiriCtxError::Config(format!(
            "browser role {role} has no session"
        ))),
    }
}

fn focus_role_target(cfg: &Config, ctx: Context, role: &Role, session: &str) -> Result<()> {
    let sock = herdr_sock_for_session(session)?;
    if !sock.is_socket() {
        return Ok(());
    }
    let ctx_cfg = context_cfg(cfg, ctx)?;
    let workspaces = herdr_sock_json(&sock, &["workspace", "list"])?;
    if ctx == Context::Admin {
        if let Some(wsid) = workspace_id_by_label(&workspaces, "term") {
            let _ = herdr_sock_json(&sock, &["workspace", "focus", &wsid]);
        } else {
            let cwd = default_repo(ctx_cfg)?.dir.display().to_string();
            let _ = herdr_sock_json(
                &sock,
                &[
                    "workspace",
                    "create",
                    "--label",
                    "term",
                    "--cwd",
                    &cwd,
                    "--focus",
                ],
            );
        }
        return Ok(());
    }
    if let Role::Repo(label) = role {
        let repo = ctx_cfg
            .repos
            .iter()
            .find(|repo| repo.label == *label)
            .ok_or_else(|| {
                NiriCtxError::Config(format!("context {} has no repo {label}", ctx.name()))
            })?;
        if let Some(wsid) = workspace_id_by_label(&workspaces, label) {
            let _ = herdr_sock_json(&sock, &["workspace", "focus", &wsid]);
        } else {
            let _ = herdr_sock_json(
                &sock,
                &[
                    "workspace",
                    "create",
                    "--label",
                    label,
                    "--cwd",
                    &repo.dir.display().to_string(),
                    "--focus",
                ],
            );
        }
        return Ok(());
    }
    let role_label = match role {
        Role::Editor => "editor",
        Role::Agents => "agents",
        Role::Logs => "logs",
        Role::Term => "term",
        Role::All | Role::Docs | Role::Output | Role::Repo(_) => return Ok(()),
    };
    let default = default_repo(ctx_cfg)?;
    let mut wsid = focused_repo_workspace(&workspaces)
        .or_else(|| workspace_id_by_label(&workspaces, &default.label));
    if wsid.is_none() {
        let created = herdr_sock_json(
            &sock,
            &[
                "workspace",
                "create",
                "--label",
                &default.label,
                "--cwd",
                &default.dir.display().to_string(),
                "--focus",
            ],
        )?;
        wsid = pointer_str(&created, "/result/workspace/workspace_id");
        if role_label == "editor" {
            if let Some(tabid) = pointer_str(&created, "/result/tab/tab_id") {
                let _ = herdr_sock_json(&sock, &["tab", "rename", &tabid, "editor"]);
            }
            if let Some(pane) = pointer_str(&created, "/result/root_pane/pane_id") {
                run_editor(&sock, &pane);
            }
            return Ok(());
        }
    }
    let Some(wsid) = wsid else {
        return Ok(());
    };
    let tabs = herdr_sock_json(&sock, &["tab", "list", "--workspace", &wsid])?;
    if let Some(tabid) = tab_id_by_label(&tabs, role_label) {
        let _ = herdr_sock_json(&sock, &["tab", "focus", &tabid]);
        return Ok(());
    }
    let created = herdr_sock_json(
        &sock,
        &[
            "tab",
            "create",
            "--workspace",
            &wsid,
            "--label",
            role_label,
            "--focus",
        ],
    )?;
    if role_label == "editor" {
        if let Some(pane) = pointer_str(&created, "/result/root_pane/pane_id") {
            run_editor(&sock, &pane);
        }
    }
    Ok(())
}

fn ensure_tmux_target(cfg: &Config, ctx: Context, role: &Role, session: &str) -> Result<()> {
    let exists = Command::new("tmux")
        .args(["has-session", "-t", session])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false);
    let ctx_cfg = context_cfg(cfg, ctx)?;
    let window = tmux_target_window(cfg, ctx, role, session)?;
    if tmux_window_exists(session, &window) {
        return Ok(());
    }
    let repo = if ctx == Context::Admin {
        default_repo(ctx_cfg)?
    } else {
        let label = window
            .split_once('/')
            .map_or(window.as_str(), |(label, _)| label);
        ctx_cfg
            .repos
            .iter()
            .find(|repo| repo.label == label)
            .unwrap_or(default_repo(ctx_cfg)?)
    };
    let cwd = repo.dir.display().to_string();
    let editor = window.ends_with("/editor");
    let mut command = Command::new("tmux");
    if exists {
        command.args(["new-window", "-d", "-t", session, "-c", &cwd, "-n", &window]);
    } else {
        command.args([
            "new-session",
            "-d",
            "-s",
            session,
            "-c",
            &cwd,
            "-n",
            &window,
        ]);
    }
    if editor {
        command.arg("nvim");
    }
    let _ = command.status();
    Ok(())
}

fn tmux_window_exists(session: &str, window: &str) -> bool {
    Command::new("tmux")
        .args(["list-windows", "-F", "#{window_name}", "-t", session])
        .stdin(Stdio::null())
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .is_some_and(|names| names.lines().any(|name| name == window))
}

fn tmux_target_window(cfg: &Config, ctx: Context, role: &Role, session: &str) -> Result<String> {
    if ctx == Context::Admin {
        return Ok("term".to_string());
    }
    if let Role::Repo(label) = role {
        let ctx_cfg = context_cfg(cfg, ctx)?;
        if !ctx_cfg.repos.iter().any(|repo| repo.label == *label) {
            return Err(NiriCtxError::Config(format!(
                "context {} has no repo {label}",
                ctx.name()
            )));
        }
        return Ok(format!("{label}/term"));
    }
    let role = match role {
        Role::Editor => "editor",
        Role::Agents => "agents",
        Role::Logs => "logs",
        Role::Term => "term",
        Role::All | Role::Docs | Role::Output | Role::Repo(_) => return Ok("term".to_string()),
    };
    let current = Command::new("tmux")
        .args(["display-message", "-p", "-t", session, "#{window_name}"])
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|text| text.trim().to_string());
    let repo = current
        .as_deref()
        .and_then(|name| name.split_once('/').map(|(repo, _)| repo.to_string()))
        .unwrap_or_else(|| {
            context_cfg(cfg, ctx)
                .ok()
                .and_then(|ctx_cfg| default_repo(ctx_cfg).ok())
                .map(|repo| repo.label.clone())
                .unwrap_or_else(|| "term".to_string())
        });
    Ok(format!("{repo}/{role}"))
}

fn herdr_sock_json(sock: &Path, args: &[&str]) -> Result<serde_json::Value> {
    let mut command = Command::new("herdr");
    command.args(args);
    command.env("HERDR_SOCKET_PATH", sock);
    let output = run_timeout(&mut command, Duration::from_secs(2))?;
    if !output.status.success() || output.stdout.is_empty() {
        tracing::warn!(
            ?args,
            status = ?output.status,
            stderr = %String::from_utf8_lossy(&output.stderr),
            "herdr socket call failed; treating as no-op"
        );
        return Ok(serde_json::Value::Null);
    }
    serde_json::from_slice(&output.stdout).map_err(Into::into)
}

fn run_editor(sock: &Path, pane: &str) {
    if pane
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b':' | b'_' | b'-'))
    {
        let _ = herdr_sock_json(sock, &["pane", "run", pane, "nvim"]);
    }
}

fn run_timeout(command: &mut Command, timeout: Duration) -> Result<std::process::Output> {
    command.stdin(Stdio::null());
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|source| NiriCtxError::io("process", source))?;
    let deadline = Instant::now() + timeout;
    loop {
        if child
            .try_wait()
            .map_err(|source| NiriCtxError::io("process", source))?
            .is_some()
        {
            return child
                .wait_with_output()
                .map_err(|source| NiriCtxError::io("process", source));
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            return child
                .wait_with_output()
                .map_err(|source| NiriCtxError::io("process", source));
        }
        thread::sleep(Duration::from_millis(25));
    }
}

fn herdr_sock_for_session(session: &str) -> Result<PathBuf> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| NiriCtxError::Config("HOME is not set".to_string()))?;
    Ok(home
        .join(".config/herdr/sessions")
        .join(session)
        .join("herdr.sock"))
}

fn valid_session_name(session: &str) -> bool {
    let Some((ctx, suffix)) = session.split_once('-') else {
        return false;
    };
    !ctx.is_empty()
        && ctx.bytes().all(|b| b.is_ascii_alphabetic())
        && matches!(suffix, "work" | "dev" | "agents" | "logs" | "terminal")
}

fn context_cfg(cfg: &Config, ctx: Context) -> Result<&ContextConfig> {
    cfg.context(ctx)
        .ok_or_else(|| NiriCtxError::UnknownContext(ctx.to_string()))
}

fn default_repo(ctx: &ContextConfig) -> Result<&RepoConfig> {
    ctx.repos
        .first()
        .ok_or_else(|| NiriCtxError::Config(format!("context {} has no repos", ctx.name)))
}

fn workspace_id_by_label(value: &serde_json::Value, label: &str) -> Option<String> {
    value
        .pointer("/result/workspaces")
        .and_then(serde_json::Value::as_array)?
        .iter()
        .find(|workspace| workspace.get("label").and_then(serde_json::Value::as_str) == Some(label))
        .and_then(|workspace| workspace.get("workspace_id"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
}

fn focused_repo_workspace(value: &serde_json::Value) -> Option<String> {
    value
        .pointer("/result/workspaces")
        .and_then(serde_json::Value::as_array)?
        .iter()
        .find(|workspace| {
            workspace
                .get("focused")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false)
                && !matches!(
                    workspace.get("label").and_then(serde_json::Value::as_str),
                    Some("editor" | "agents" | "logs" | "term")
                )
        })
        .and_then(|workspace| workspace.get("workspace_id"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
}

fn tab_id_by_label(value: &serde_json::Value, label: &str) -> Option<String> {
    value
        .pointer("/result/tabs")
        .and_then(serde_json::Value::as_array)?
        .iter()
        .find(|tab| tab.get("label").and_then(serde_json::Value::as_str) == Some(label))
        .and_then(|tab| tab.get("tab_id"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
}

fn pointer_str(value: &serde_json::Value, pointer: &str) -> Option<String> {
    value
        .pointer(pointer)
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
}

fn which(bin: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|path| {
        std::env::split_paths(&path)
            .map(|dir| dir.join(bin))
            .find(|candidate| candidate.is_file())
    })
}

trait SocketPathExt {
    fn is_socket(&self) -> bool;
}

impl SocketPathExt for Path {
    fn is_socket(&self) -> bool {
        std::fs::metadata(self)
            .map(|metadata| {
                use std::os::unix::fs::FileTypeExt;
                metadata.file_type().is_socket()
            })
            .unwrap_or(false)
    }
}

#[cfg(test)]
#[allow(dead_code)]
#[derive(Debug, Default)]
pub struct FakeSessionBackend {
    pub existing_sessions: std::collections::BTreeSet<String>,
    pub calls: Vec<String>,
    pub workspaces: std::collections::BTreeMap<String, Vec<String>>,
    pub focused_workspace: Option<String>,
    pub focused_tab: Option<String>,
}

#[cfg(test)]
impl SessionBackend for FakeSessionBackend {
    fn session_exists(&mut self, session: &str) -> Result<bool> {
        Ok(self.existing_sessions.contains(session))
    }

    fn reap_fresh_session(&mut self, session: &str) -> Result<()> {
        self.calls.push(format!("reap:{session}"));
        self.existing_sessions.remove(session);
        Ok(())
    }

    fn deep_link(&mut self, cfg: &Config, ctx: Context, role: &Role) -> Result<()> {
        if *role == Role::All {
            return Ok(());
        }
        self.calls
            .push(format!("target:{}-work:{role}", ctx.name()));
        if ctx == Context::Admin {
            self.focused_workspace = Some("term".to_string());
            self.calls.push("focus-workspace:term".to_string());
            return Ok(());
        }
        let ctx_cfg = cfg
            .context(ctx)
            .ok_or_else(|| NiriCtxError::UnknownContext(ctx.to_string()))?;
        let default = ctx_cfg
            .repos
            .first()
            .ok_or_else(|| NiriCtxError::Config(format!("context {} has no repos", ctx.name())))?
            .label
            .clone();
        if let Role::Repo(label) = role {
            if !ctx_cfg.repos.iter().any(|repo| repo.label == *label) {
                return Err(NiriCtxError::Config(format!(
                    "context {} has no repo {label}",
                    ctx.name()
                )));
            }
            if !self.workspaces.contains_key(label) {
                self.calls.push(format!("create-workspace:{label}"));
                self.workspaces.insert(label.clone(), vec!["1".to_string()]);
            }
            self.focused_workspace = Some(label.clone());
            self.calls.push(format!("focus-workspace:{label}"));
            return Ok(());
        }
        let workspace = self
            .focused_workspace
            .clone()
            .filter(|label| !matches!(label.as_str(), "editor" | "agents" | "logs" | "term"))
            .unwrap_or(default);
        let role_label = match role {
            Role::Editor => "editor",
            Role::Agents => "agents",
            Role::Logs => "logs",
            Role::Term => "term",
            Role::All | Role::Docs | Role::Output | Role::Repo(_) => return Ok(()),
        };
        let created_workspace = !self.workspaces.contains_key(&workspace);
        if created_workspace {
            self.calls.push(format!("create-workspace:{workspace}"));
            self.workspaces
                .insert(workspace.clone(), vec!["1".to_string()]);
        }
        let tabs = self
            .workspaces
            .get_mut(&workspace)
            .expect("workspace was inserted above");
        if !tabs.iter().any(|tab| tab == role_label) {
            if role_label == "editor" && created_workspace {
                self.calls
                    .push(format!("adopt-editor:{workspace}:start-nvim"));
                tabs[0] = "editor".to_string();
            } else {
                self.calls
                    .push(format!("create-tab:{workspace}:{role_label}"));
                tabs.push(role_label.to_string());
            }
        }
        self.focused_workspace = Some(workspace.clone());
        self.focused_tab = Some(role_label.to_string());
        self.calls
            .push(format!("focus-tab:{workspace}:{role_label}"));
        Ok(())
    }
}
