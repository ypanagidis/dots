use std::collections::{BTreeMap, HashSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::error::{NiriCtxError, Result};
use crate::model::Context;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Config {
    pub outputs: OutputsConfig,
    pub behavior: BehaviorConfig,
    pub terminal: TerminalConfig,
    pub browser: BrowserConfig,
    #[serde(rename = "context")]
    pub contexts: Vec<ContextConfig>,
    pub comms: CommsConfig,
    pub ambient: AmbientConfig,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OutputsConfig {
    pub main: String,
    pub top: String,
    pub vertical: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BehaviorConfig {
    pub session_backend: String,
    pub top_follow: String,
    pub launch_timeout_secs: u64,
    pub converge_iters: usize,
    pub bash_fallback: PathBuf,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TerminalConfig {
    pub program: String,
    pub fallback: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BrowserConfig {
    pub bin: PathBuf,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ContextConfig {
    pub name: String,
    pub slug: String,
    pub helium_profile: String,
    pub repos: Vec<RepoConfig>,
    pub devtools: bool,
    pub terminal_role: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RepoConfig {
    pub label: String,
    pub dir: PathBuf,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CommsConfig {
    pub apps: Vec<CommsAppConfig>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CommsAppConfig {
    pub name: String,
    pub app_id: String,
    pub launch: Vec<Vec<String>>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AmbientConfig {
    pub spotify_app_id: String,
    pub spotify_launch: Vec<Vec<String>>,
}

impl Config {
    pub fn load() -> Result<Self> {
        let repo_root = repo_root();
        let mut config = Self::default_for_repo(&repo_root);
        let contexts_path = repo_root.join(".config/niri/contexts.conf");
        if contexts_path.exists() {
            config.merge_contexts_conf(&contexts_path)?;
        } else if let Some(home) = home_dir() {
            let fallback = home.join(".config/niri/contexts.conf");
            if fallback.exists() {
                config.merge_contexts_conf(&fallback)?;
            }
        }

        if let Some(overlay_path) = overlay_path() {
            if overlay_path.exists() {
                let text = fs::read_to_string(&overlay_path)
                    .map_err(|source| NiriCtxError::io(&overlay_path, source))?;
                let overlay: ConfigOverlay = toml::from_str(&text)
                    .map_err(|err| NiriCtxError::Config(format!("{overlay_path:?}: {err}")))?;
                config.apply_overlay(overlay);
            }
        }

        config.validate()?;
        Ok(config)
    }

    pub fn default_for_repo(repo_root: impl AsRef<Path>) -> Self {
        let repo_root = repo_root.as_ref();
        let home = home_dir().unwrap_or_else(|| PathBuf::from("/home/yiannis"));
        Self {
            outputs: OutputsConfig {
                main: "DP-1".to_string(),
                top: "DP-2".to_string(),
                vertical: "HDMI-A-1".to_string(),
            },
            behavior: BehaviorConfig {
                session_backend: "herdr".to_string(),
                top_follow: "off".to_string(),
                launch_timeout_secs: 10,
                converge_iters: 4,
                bash_fallback: repo_root.join("bin/niri-ctx"),
            },
            terminal: TerminalConfig {
                program: "ghostty".to_string(),
                fallback: None,
            },
            browser: BrowserConfig {
                bin: PathBuf::from("/opt/helium-browser-bin/helium"),
            },
            contexts: vec![
                context(
                    "UP",
                    "up",
                    "Profile 1",
                    &[("mono", home.join("Developer/Work/UP/mono"))],
                ),
                context(
                    "Webroot",
                    "webroot",
                    "Profile 3",
                    &[("webroot", home.join("Developer/Work/Webroot"))],
                ),
                context(
                    "Sealant",
                    "sealant",
                    "Default",
                    &[
                        ("core", home.join("Developer/OSS/Sealant/Core")),
                        ("sealantd", home.join("Developer/OSS/Sealant/Sealantd")),
                    ],
                ),
                context(
                    "Side",
                    "side",
                    "Default",
                    &[("sandbox", home.join("Developer/sandbox"))],
                ),
                ContextConfig {
                    name: "Admin".to_string(),
                    slug: "admin".to_string(),
                    helium_profile: "Default".to_string(),
                    repos: vec![RepoConfig {
                        label: "term".to_string(),
                        dir: home,
                    }],
                    devtools: false,
                    terminal_role: Some("term".to_string()),
                },
            ],
            comms: CommsConfig {
                apps: vec![
                    CommsAppConfig {
                        name: "slack".to_string(),
                        app_id: "slack".to_string(),
                        launch: vec![vec!["slack".to_string()]],
                    },
                    CommsAppConfig {
                        name: "telegram".to_string(),
                        app_id: "org.telegram.desktop".to_string(),
                        launch: vec![
                            vec!["Telegram".to_string()],
                            vec!["telegram-desktop".to_string()],
                        ],
                    },
                    CommsAppConfig {
                        name: "discord".to_string(),
                        app_id: "discord".to_string(),
                        launch: vec![vec!["discord".to_string()]],
                    },
                ],
            },
            ambient: AmbientConfig {
                spotify_app_id: "Spotify".to_string(),
                spotify_launch: vec![
                    vec!["spotify-launcher".to_string()],
                    vec!["spotify".to_string()],
                ],
            },
        }
    }

    pub fn context(&self, ctx: Context) -> Option<&ContextConfig> {
        self.contexts
            .iter()
            .find(|candidate| candidate.name.eq_ignore_ascii_case(ctx.name()))
    }

    #[allow(dead_code)]
    pub fn context_by_name(&self, name: &str) -> Option<&ContextConfig> {
        self.contexts
            .iter()
            .find(|candidate| candidate.name.eq_ignore_ascii_case(name))
    }

    #[allow(dead_code)]
    pub fn context_for_slug(&self, slug: &str) -> Option<&ContextConfig> {
        self.contexts
            .iter()
            .find(|candidate| candidate.slug == slug)
    }

    pub fn work_app_id(&self, ctx: Context) -> Result<String> {
        let cfg = self
            .context(ctx)
            .ok_or_else(|| NiriCtxError::UnknownContext(ctx.to_string()))?;
        Ok(format!("dev.yiannis.niri.{}.work", cfg.slug))
    }

    pub fn write_frozen_toml(&self) -> Result<PathBuf> {
        let path = overlay_path().ok_or_else(|| {
            NiriCtxError::Config("could not determine ~/.config/niri-ctx/config.toml".to_string())
        })?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|source| NiriCtxError::io(parent, source))?;
        }
        let text = toml::to_string_pretty(self)
            .map_err(|err| NiriCtxError::Config(format!("serialize config: {err}")))?;
        fs::write(&path, text).map_err(|source| NiriCtxError::io(&path, source))?;
        Ok(path)
    }

    fn apply_overlay(&mut self, overlay: ConfigOverlay) {
        if let Some(outputs) = overlay.outputs {
            if let Some(main) = outputs.main {
                self.outputs.main = main;
            }
            if let Some(top) = outputs.top {
                self.outputs.top = top;
            }
            if let Some(vertical) = outputs.vertical {
                self.outputs.vertical = vertical;
            }
        }
        if let Some(behavior) = overlay.behavior {
            if let Some(session_backend) = behavior.session_backend {
                self.behavior.session_backend = session_backend;
            }
            if let Some(top_follow) = behavior.top_follow {
                self.behavior.top_follow = top_follow;
            }
            if let Some(launch_timeout_secs) = behavior.launch_timeout_secs {
                self.behavior.launch_timeout_secs = launch_timeout_secs;
            }
            if let Some(converge_iters) = behavior.converge_iters {
                self.behavior.converge_iters = converge_iters;
            }
            if let Some(bash_fallback) = behavior.bash_fallback {
                self.behavior.bash_fallback = bash_fallback;
            }
        }
        if let Some(terminal) = overlay.terminal {
            if let Some(program) = terminal.program {
                self.terminal.program = program;
            }
            if terminal.fallback.is_some() {
                self.terminal.fallback = terminal.fallback;
            }
        }
        if let Some(browser) = overlay.browser {
            if let Some(bin) = browser.bin {
                self.browser.bin = bin;
            }
        }
        if let Some(contexts) = overlay.contexts {
            self.contexts = contexts;
        }
        if let Some(comms) = overlay.comms {
            self.comms = comms;
        }
        if let Some(ambient) = overlay.ambient {
            self.ambient = ambient;
        }
    }

    fn merge_contexts_conf(&mut self, path: &Path) -> Result<()> {
        let output = Command::new("bash")
            .arg("-c")
            .arg(
                "source \"$1\"; declare -p CTX_REPOS CTX_HELIUM_PROFILE; \
                 printf 'MAIN_OUTPUT=%s\\n' \"$MAIN_OUTPUT\"; \
                 printf 'TOP_OUTPUT=%s\\n' \"$TOP_OUTPUT\"; \
                 printf 'COMMS_OUTPUT=%s\\n' \"$COMMS_OUTPUT\"; \
                 printf 'HELIUM_BIN=%s\\n' \"$HELIUM_BIN\"; \
                 printf 'CONTEXT_TERMINAL=%s\\n' \"$CONTEXT_TERMINAL\"; \
                 printf 'SESSION_BACKEND=%s\\n' \"${SESSION_BACKEND:-${AGENTS_BACKEND:-herdr}}\"; \
                 printf 'TOP_FOLLOW=%s\\n' \"${TOP_FOLLOW:-devtools}\"",
            )
            .arg("bash")
            .arg(path)
            .output()
            .map_err(|source| NiriCtxError::io(path, source))?;
        if !output.status.success() {
            return Err(NiriCtxError::Config(format!(
                "failed to source {}: {}",
                path.display(),
                String::from_utf8_lossy(&output.stderr)
            )));
        }
        let stdout = String::from_utf8(output.stdout).map_err(|err| {
            NiriCtxError::Config(format!("contexts.conf output was not UTF-8: {err}"))
        })?;
        let derived = DerivedConfig::parse(&stdout)?;
        self.outputs.main = derived
            .vars
            .get("MAIN_OUTPUT")
            .cloned()
            .unwrap_or_else(|| self.outputs.main.clone());
        self.outputs.top = derived
            .vars
            .get("TOP_OUTPUT")
            .cloned()
            .unwrap_or_else(|| self.outputs.top.clone());
        self.outputs.vertical = derived
            .vars
            .get("COMMS_OUTPUT")
            .cloned()
            .unwrap_or_else(|| self.outputs.vertical.clone());
        if let Some(bin) = derived.vars.get("HELIUM_BIN") {
            self.browser.bin = PathBuf::from(bin);
        }
        if let Some(program) = derived.vars.get("CONTEXT_TERMINAL") {
            self.terminal.program = program.clone();
        }
        if let Some(backend) = derived.vars.get("SESSION_BACKEND") {
            self.behavior.session_backend = backend.clone();
        }
        if let Some(top_follow) = derived.vars.get("TOP_FOLLOW") {
            self.behavior.top_follow = top_follow.clone();
        }

        for ctx in &mut self.contexts {
            if let Some(repos) = derived.repos.get(&ctx.name) {
                ctx.repos = parse_repos(repos)?;
            }
            if let Some(profile) = derived.helium_profiles.get(&ctx.name) {
                ctx.helium_profile = profile.clone();
            }
        }
        Ok(())
    }

    pub fn validate(&self) -> Result<Vec<String>> {
        let mut warnings = Vec::new();
        if self.outputs.main.is_empty()
            || self.outputs.top.is_empty()
            || self.outputs.vertical.is_empty()
        {
            return Err(NiriCtxError::Config(
                "output names must be non-empty".to_string(),
            ));
        }
        if !matches!(self.behavior.session_backend.as_str(), "herdr" | "tmux") {
            return Err(NiriCtxError::Config(format!(
                "invalid session_backend {}",
                self.behavior.session_backend
            )));
        }
        if !matches!(
            self.behavior.top_follow.as_str(),
            "off" | "devtools" | "ambient"
        ) {
            return Err(NiriCtxError::Config(format!(
                "invalid top_follow {}",
                self.behavior.top_follow
            )));
        }
        if !matches!(self.terminal.program.as_str(), "alacritty" | "ghostty") {
            return Err(NiriCtxError::Config(format!(
                "invalid terminal program {}",
                self.terminal.program
            )));
        }
        let mut names = HashSet::new();
        for ctx in &self.contexts {
            if !names.insert(ctx.name.to_ascii_lowercase()) {
                return Err(NiriCtxError::Config(format!(
                    "duplicate context {}",
                    ctx.name
                )));
            }
            if !valid_slug(&ctx.slug) {
                return Err(NiriCtxError::Config(format!("invalid slug {}", ctx.slug)));
            }
            if ctx.repos.is_empty() {
                return Err(NiriCtxError::Config(format!(
                    "context {} has no repos",
                    ctx.name
                )));
            }
            for repo in &ctx.repos {
                if !repo.dir.exists() {
                    warnings.push(format!(
                        "repo {}={} does not exist",
                        repo.label,
                        repo.dir.display()
                    ));
                }
            }
        }
        Ok(warnings)
    }
}

#[derive(Debug, Clone, serde::Deserialize)]
struct ConfigOverlay {
    outputs: Option<OutputsOverlay>,
    behavior: Option<BehaviorOverlay>,
    terminal: Option<TerminalOverlay>,
    browser: Option<BrowserOverlay>,
    #[serde(rename = "context")]
    contexts: Option<Vec<ContextConfig>>,
    comms: Option<CommsConfig>,
    ambient: Option<AmbientConfig>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct OutputsOverlay {
    main: Option<String>,
    top: Option<String>,
    vertical: Option<String>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct BehaviorOverlay {
    session_backend: Option<String>,
    top_follow: Option<String>,
    launch_timeout_secs: Option<u64>,
    converge_iters: Option<usize>,
    bash_fallback: Option<PathBuf>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct TerminalOverlay {
    program: Option<String>,
    fallback: Option<String>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct BrowserOverlay {
    bin: Option<PathBuf>,
}

fn context(name: &str, slug: &str, profile: &str, repos: &[(&str, PathBuf)]) -> ContextConfig {
    ContextConfig {
        name: name.to_string(),
        slug: slug.to_string(),
        helium_profile: profile.to_string(),
        repos: repos
            .iter()
            .map(|(label, dir)| RepoConfig {
                label: (*label).to_string(),
                dir: dir.clone(),
            })
            .collect(),
        devtools: true,
        terminal_role: None,
    }
}

#[derive(Debug, Default)]
struct DerivedConfig {
    repos: BTreeMap<String, String>,
    helium_profiles: BTreeMap<String, String>,
    vars: BTreeMap<String, String>,
}

impl DerivedConfig {
    fn parse(text: &str) -> Result<Self> {
        let mut derived = DerivedConfig::default();
        for line in text.lines() {
            if line.starts_with("declare -A CTX_REPOS=") {
                derived.repos = parse_declare_assoc(line, "CTX_REPOS")?;
            } else if line.starts_with("declare -A CTX_HELIUM_PROFILE=") {
                derived.helium_profiles = parse_declare_assoc(line, "CTX_HELIUM_PROFILE")?;
            } else if let Some((key, value)) = line.split_once('=') {
                derived.vars.insert(key.to_string(), value.to_string());
            }
        }
        Ok(derived)
    }
}

fn parse_declare_assoc(line: &str, name: &str) -> Result<BTreeMap<String, String>> {
    let prefix = format!("declare -A {name}=");
    let body = line
        .strip_prefix(&prefix)
        .ok_or_else(|| NiriCtxError::Config(format!("missing declare prefix for {name}")))?;
    let body = body.trim().trim_start_matches('(').trim_end_matches(')');
    let mut map = BTreeMap::new();
    let chars = body.as_bytes();
    let mut i = 0;
    while i < chars.len() {
        while i < chars.len() && chars[i].is_ascii_whitespace() {
            i += 1;
        }
        if i >= chars.len() {
            break;
        }
        if chars.get(i) != Some(&b'[') {
            return Err(NiriCtxError::Config(format!(
                "bad declare entry in {name}: {body}"
            )));
        }
        i += 1;
        let key_start = i;
        while i < chars.len() && chars[i] != b']' {
            i += 1;
        }
        let key = &body[key_start..i];
        i += 1;
        if chars.get(i) != Some(&b'=') {
            return Err(NiriCtxError::Config(format!(
                "bad declare assignment in {name}: {body}"
            )));
        }
        i += 1;
        let value = if chars.get(i) == Some(&b'"') {
            i += 1;
            let mut value = String::new();
            while i < chars.len() {
                match chars[i] {
                    b'\\' if i + 1 < chars.len() => {
                        i += 1;
                        value.push(chars[i] as char);
                        i += 1;
                    }
                    b'"' => {
                        i += 1;
                        break;
                    }
                    byte => {
                        value.push(byte as char);
                        i += 1;
                    }
                }
            }
            value
        } else {
            let value_start = i;
            while i < chars.len() && !chars[i].is_ascii_whitespace() {
                i += 1;
            }
            body[value_start..i].to_string()
        };
        map.insert(key.to_string(), value);
    }
    Ok(map)
}

fn parse_repos(value: &str) -> Result<Vec<RepoConfig>> {
    value
        .split_whitespace()
        .map(|entry| {
            let (label, dir) = entry.split_once('=').ok_or_else(|| {
                NiriCtxError::Config(format!("repo entry must be label=dir: {entry}"))
            })?;
            Ok(RepoConfig {
                label: label.to_string(),
                dir: PathBuf::from(dir),
            })
        })
        .collect()
}

fn valid_slug(slug: &str) -> bool {
    !slug.is_empty()
        && slug.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_' || byte == b'-'
        })
}

pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .unwrap_or_else(|| env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
}

fn home_dir() -> Option<PathBuf> {
    env::var_os("HOME").map(PathBuf::from)
}

fn overlay_path() -> Option<PathBuf> {
    home_dir().map(|home| home.join(".config/niri-ctx/config.toml"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn parses_declare_associative_arrays() {
        let line = r#"declare -A CTX_REPOS=([Side]="sandbox=/tmp/sandbox" [UP]="mono=/tmp/up mono2=/tmp/up2" )"#;
        let parsed = parse_declare_assoc(line, "CTX_REPOS").expect("parse");
        assert_eq!(parsed.get("UP").expect("UP"), "mono=/tmp/up mono2=/tmp/up2");
    }

    #[test]
    fn derives_from_contexts_conf_fixture() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("contexts.conf");
        let mut file = fs::File::create(&path).expect("fixture");
        writeln!(
            file,
            r#"
declare -A CTX_REPOS=(
  [UP]="mono=$HOME/Developer/Work/UP/mono"
  [Webroot]="webroot=$HOME/Developer/Work/Webroot"
  [Sealant]="core=$HOME/Developer/OSS/Sealant/Core sealantd=$HOME/Developer/OSS/Sealant/Sealantd"
  [Side]="sandbox=$HOME/Developer/sandbox"
  [Admin]="term=$HOME"
)
declare -A CTX_HELIUM_PROFILE=(
  [UP]="Profile 1" [Webroot]="Profile 3" [Sealant]="Default" [Side]="Default" [Admin]="Default"
)
MAIN_OUTPUT="DP-1"; TOP_OUTPUT="DP-2"; COMMS_OUTPUT="HDMI-A-1"
HELIUM_BIN="${{HELIUM_BIN:-/opt/helium-browser-bin/helium}}"
CONTEXT_TERMINAL="${{NIRI_CONTEXT_TERMINAL:-ghostty}}"
SESSION_BACKEND="${{SESSION_BACKEND:-herdr}}"
TOP_FOLLOW="off"
"#
        )
        .expect("write");
        let mut cfg = Config::default_for_repo("/repo");
        cfg.merge_contexts_conf(&path).expect("derive");
        assert_eq!(cfg.outputs.main, "DP-1");
        assert_eq!(cfg.outputs.top, "DP-2");
        assert_eq!(cfg.outputs.vertical, "HDMI-A-1");
        assert_eq!(
            cfg.context(Context::UP).expect("up").helium_profile,
            "Profile 1"
        );
        assert_eq!(
            cfg.context(Context::Sealant).expect("sealant").repos.len(),
            2
        );
        assert_eq!(cfg.terminal.program, "ghostty");
    }

    #[test]
    fn rejects_duplicate_contexts() {
        let mut cfg = Config::default_for_repo("/repo");
        cfg.contexts.push(cfg.contexts[0].clone());
        assert!(cfg.validate().is_err());
    }

    #[test]
    fn partial_overlay_preserves_derived_config() {
        let mut cfg = Config::default_for_repo("/repo");
        let overlay: ConfigOverlay = toml::from_str(
            r#"
[behavior]
launch_timeout_secs = 3

[terminal]
program = "alacritty"
"#,
        )
        .expect("overlay");
        cfg.apply_overlay(overlay);
        assert_eq!(cfg.behavior.launch_timeout_secs, 3);
        assert_eq!(cfg.terminal.program, "alacritty");
        assert_eq!(cfg.outputs.main, "DP-1");
        assert_eq!(cfg.contexts.len(), 5);
    }
}
