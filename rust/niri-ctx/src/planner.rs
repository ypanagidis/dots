use std::collections::BTreeSet;
use std::time::Duration;

use crate::config::{CommsAppConfig, Config};
use crate::error::{NiriCtxError, Result};
use crate::model::{
    BrowserRole, CommsAppKind, Context, ContextArg, LaunchFailure, Role, WindowId, WindowMatcher,
    WorkspaceRef,
};
use crate::niri::{SizeChange, Window};
use crate::state::DesktopState;

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq)]
pub enum Effect {
    FocusOutput {
        output: String,
    },
    FocusWorkspace {
        output: String,
        ws: WorkspaceRef,
    },
    FocusWindow {
        id: WindowId,
    },
    MoveWindowToWorkspace {
        id: WindowId,
        ws: WorkspaceRef,
        focus: bool,
    },
    MoveColumnToIndex {
        index: usize,
    },
    ExpelWindowFromColumn,
    ConsumeWindowIntoColumn,
    SetColumnWidth {
        change: SizeChange,
    },
    SetWindowHeight {
        id: WindowId,
        change: SizeChange,
    },
    SpawnTerminal {
        ctx: Context,
        role: Role,
        app_id: String,
        title: String,
    },
    SpawnBrowser {
        ctx: Context,
        role: BrowserRole,
        profile: String,
    },
    SpawnCommsApp {
        app: String,
    },
    SpawnSpotify,
    WaitForWindow {
        matcher: WindowMatcher,
        timeout: Duration,
        on_fail: LaunchFailure,
    },
    WriteBrowserCache {
        ctx_slug: String,
        role: BrowserRole,
        id: Option<WindowId>,
    },
    Log {
        level: String,
        msg: String,
    },
    Fail {
        diag: String,
    },
}

impl Effect {
    pub fn is_mutating(&self) -> bool {
        !matches!(self, Effect::Log { .. } | Effect::Fail { .. })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Goal {
    Open { ctx: ContextArg, role: Role },
    Scratch,
    Comms,
    Spotify,
    TopAmbient,
    DevtoolsHere,
    Startup,
    Current,
}

pub fn plan(cfg: &Config, state: &DesktopState, goal: &Goal) -> Result<Vec<Effect>> {
    let effects = match goal {
        Goal::Open { ctx, role } => {
            let ctx = resolve_context_arg(cfg, state, *ctx)?;
            plan_open(cfg, state, ctx, role)?
        }
        Goal::Scratch => plan_scratch(cfg, state)?,
        Goal::Comms => plan_comms(cfg, state)?,
        Goal::Spotify => plan_spotify(cfg, state)?,
        Goal::TopAmbient => plan_top_ambient(cfg, state),
        Goal::DevtoolsHere => plan_devtools_here(cfg, state)?,
        Goal::Startup => focus_workspace_guarded(state, &cfg.outputs.main, "UP"),
        Goal::Current => Vec::new(),
    };
    Ok(simplify_focus(state, effects))
}

/// Intra-plan focus simulation. Sub-planners each consult the same immutable
/// snapshot, so a composed plan can repeat focus effects an earlier effect in
/// the same plan already achieves — and executing a repeated focus-workspace
/// would bounce via `workspace-auto-back-and-forth`. Fold over the plan
/// tracking what focus WILL be at each point and drop effects that are
/// already satisfied. Conservative: any effect with unknowable focus fallout
/// (spawns, waits) clears the simulated state so later focus effects are kept.
fn simplify_focus(state: &DesktopState, effects: Vec<Effect>) -> Vec<Effect> {
    let lower = |s: &str| s.to_ascii_lowercase();
    let ws_of_window = |id: WindowId| -> Option<(String, String)> {
        let window = state.window(id)?;
        let ws = state.workspace(window.workspace_id)?;
        Some((lower(ws.name.as_deref()?), ws.output.clone()))
    };

    let mut focused_ws: Option<String> = state
        .focused_workspace
        .and_then(|id| state.workspace(id))
        .and_then(|ws| ws.name.as_deref().map(lower));
    let mut focused_output: Option<String> = state.focused_output().map(str::to_string);
    let mut focused_window: Option<WindowId> = state.focused_window;
    // Workspace-activation overrides accumulated by this plan, keyed by output.
    let mut activated: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    let active_on = |activated: &std::collections::HashMap<String, String>, output: &str| {
        activated
            .get(output)
            .cloned()
            .or_else(|| state.active_workspace_name_on_output(output).map(&lower))
    };

    let mut kept = Vec::with_capacity(effects.len());
    for effect in effects {
        match &effect {
            Effect::FocusOutput { output } => {
                if focused_output.as_deref() == Some(output.as_str()) {
                    continue;
                }
                focused_ws = active_on(&activated, output);
                focused_output = Some(output.clone());
                focused_window = None;
            }
            Effect::FocusWorkspace { output, ws } => {
                if let WorkspaceRef::Name(name) = ws {
                    let name = lower(name);
                    if focused_ws.as_deref() == Some(name.as_str()) {
                        continue;
                    }
                    focused_ws = Some(name.clone());
                    activated.insert(output.clone(), name);
                } else {
                    focused_ws = None;
                }
                focused_output = Some(output.clone());
                focused_window = None;
            }
            Effect::FocusWindow { id } => {
                if focused_window == Some(*id) {
                    continue;
                }
                focused_window = Some(*id);
                match ws_of_window(*id) {
                    Some((ws, output)) => {
                        activated.insert(output.clone(), ws.clone());
                        focused_ws = Some(ws);
                        focused_output = Some(output);
                    }
                    None => {
                        focused_ws = None;
                        focused_output = None;
                    }
                }
            }
            Effect::MoveWindowToWorkspace { id, ws, focus } => {
                if *focus {
                    focused_window = Some(*id);
                    if let WorkspaceRef::Name(name) = ws {
                        focused_ws = Some(lower(name));
                    } else {
                        focused_ws = None;
                    }
                    focused_output = None;
                } else if focused_window == Some(*id) {
                    // niri refocuses some other window on the current workspace
                    focused_window = None;
                }
            }
            Effect::SpawnTerminal { .. }
            | Effect::SpawnBrowser { .. }
            | Effect::SpawnCommsApp { .. }
            | Effect::SpawnSpotify
            | Effect::WaitForWindow { .. } => {
                // A newly mapped window may take focus; everything is unknown.
                focused_ws = None;
                focused_output = None;
                focused_window = None;
            }
            Effect::MoveColumnToIndex { .. }
            | Effect::ExpelWindowFromColumn
            | Effect::ConsumeWindowIntoColumn
            | Effect::SetColumnWidth { .. }
            | Effect::SetWindowHeight { .. }
            | Effect::WriteBrowserCache { .. }
            | Effect::Log { .. }
            | Effect::Fail { .. } => {}
        }
        kept.push(effect);
    }
    kept
}

pub fn resolve_context_arg(cfg: &Config, state: &DesktopState, ctx: ContextArg) -> Result<Context> {
    match ctx {
        ContextArg::Context(ctx) => Ok(ctx),
        ContextArg::Current => state
            .current_context(cfg)
            .ok_or_else(|| NiriCtxError::UnknownContext("current".to_string())),
    }
}

fn plan_open(cfg: &Config, state: &DesktopState, ctx: Context, role: &Role) -> Result<Vec<Effect>> {
    match role {
        Role::All => plan_open_all(cfg, state, ctx),
        Role::Docs => plan_browser_card(cfg, state, ctx, BrowserRole::Docs, true),
        Role::Output => plan_browser_card(cfg, state, ctx, BrowserRole::Output, true),
        Role::Editor | Role::Agents | Role::Logs | Role::Term | Role::Repo(_) => {
            plan_work_card(cfg, state, ctx, role, true)
        }
    }
}

fn plan_open_all(cfg: &Config, state: &DesktopState, ctx: Context) -> Result<Vec<Effect>> {
    let mut effects = focus_workspace_guarded(state, &cfg.outputs.main, ctx.name());
    effects.extend(plan_browser_card(
        cfg,
        state,
        ctx,
        BrowserRole::Docs,
        false,
    )?);
    let work_role = cfg.terminal_role_for_open_all(ctx);
    effects.extend(plan_work_card(cfg, state, ctx, &work_role, false)?);

    let ctx_cfg = cfg
        .context(ctx)
        .ok_or_else(|| NiriCtxError::UnknownContext(ctx.to_string()))?;
    let docs = browser_window(state, &ctx_cfg.slug, BrowserRole::Docs);
    let work = work_window(cfg, state, ctx)?;
    if let (Some(docs), Some(work)) = (docs, work) {
        effects.extend(flatten_pair_if_stacked(docs, work));
        effects.extend(ensure_column(docs, 1));
        effects.extend(ensure_column(work, 2));
        effects.extend(focus_workspace_guarded(
            state,
            &cfg.outputs.main,
            ctx.name(),
        ));
        if !docs.is_focused {
            effects.push(Effect::FocusWindow { id: docs.id });
        }
    }
    Ok(effects)
}

fn plan_browser_card(
    cfg: &Config,
    state: &DesktopState,
    ctx: Context,
    role: BrowserRole,
    final_focus: bool,
) -> Result<Vec<Effect>> {
    let ctx_cfg = cfg
        .context(ctx)
        .ok_or_else(|| NiriCtxError::UnknownContext(ctx.to_string()))?;
    let mut effects = focus_workspace_guarded(state, &cfg.outputs.main, ctx.name());
    let target_ws = state
        .workspace_by_name(ctx.name())
        .map(|workspace| workspace.id);
    if let Some(window) = browser_window(state, &ctx_cfg.slug, role) {
        if Some(window.workspace_id) != target_ws {
            effects.push(Effect::MoveWindowToWorkspace {
                id: window.id,
                ws: WorkspaceRef::name(ctx.name()),
                focus: false,
            });
        }
        if final_focus && !window.is_focused {
            effects.push(Effect::FocusWindow { id: window.id });
        }
    } else {
        let before = state
            .windows
            .iter()
            .filter(|window| window.app_id == "helium")
            .map(|window| window.id)
            .collect::<BTreeSet<_>>();
        effects.push(Effect::SpawnBrowser {
            ctx,
            role,
            profile: ctx_cfg.helium_profile.clone(),
        });
        effects.push(Effect::WaitForWindow {
            matcher: WindowMatcher::NewAppIdExcluding {
                app_id: "helium".to_string(),
                before,
            },
            timeout: Duration::from_secs(cfg.behavior.launch_timeout_secs),
            on_fail: LaunchFailure {
                command: format!("helium {}", role.as_str()),
                app_id: "helium".to_string(),
                cause: "window never appeared".to_string(),
            },
        });
        effects.push(Effect::WriteBrowserCache {
            ctx_slug: ctx_cfg.slug.clone(),
            role,
            id: None,
        });
    }
    Ok(effects)
}

fn plan_work_card(
    cfg: &Config,
    state: &DesktopState,
    ctx: Context,
    role: &Role,
    final_focus: bool,
) -> Result<Vec<Effect>> {
    let app_id = cfg.work_app_id(ctx)?;
    let mut effects = focus_workspace_guarded(state, &cfg.outputs.main, ctx.name());
    let target_ws = state
        .workspace_by_name(ctx.name())
        .map(|workspace| workspace.id);
    if let Some(window) = state.oldest_window_by_app_id(&app_id) {
        if Some(window.workspace_id) != target_ws {
            effects.push(Effect::MoveWindowToWorkspace {
                id: window.id,
                ws: WorkspaceRef::name(ctx.name()),
                focus: false,
            });
        }
        if final_focus && !window.is_focused {
            effects.push(Effect::FocusWindow { id: window.id });
        }
    } else {
        effects.push(Effect::SpawnTerminal {
            ctx,
            role: role.clone(),
            app_id: app_id.clone(),
            title: format!("{}-work", ctx.name()),
        });
        effects.push(Effect::WaitForWindow {
            matcher: WindowMatcher::AppIdExact(app_id.clone()),
            timeout: Duration::from_secs(cfg.behavior.launch_timeout_secs),
            on_fail: LaunchFailure {
                command: format!("terminal {ctx} {role}"),
                app_id,
                cause: "window never appeared".to_string(),
            },
        });
    }
    Ok(effects)
}

fn plan_scratch(cfg: &Config, state: &DesktopState) -> Result<Vec<Effect>> {
    let mut effects = focus_workspace_guarded(state, &cfg.outputs.main, "scratch");
    let docs = browser_window(state, "scratch", BrowserRole::Docs);
    let term = state.oldest_window_by_app_id("dev.yiannis.niri.scratch.term");
    let target_ws = state
        .workspace_by_name("scratch")
        .map(|workspace| workspace.id);
    if docs.is_none() {
        effects.push(Effect::SpawnBrowser {
            ctx: Context::UP,
            role: BrowserRole::Docs,
            profile: "Default".to_string(),
        });
        effects.push(Effect::WaitForWindow {
            matcher: WindowMatcher::NewAppIdExcluding {
                app_id: "helium".to_string(),
                before: state
                    .windows
                    .iter()
                    .filter(|window| window.app_id == "helium")
                    .map(|window| window.id)
                    .collect(),
            },
            timeout: Duration::from_secs(cfg.behavior.launch_timeout_secs),
            on_fail: LaunchFailure {
                command: "helium scratch docs".to_string(),
                app_id: "helium".to_string(),
                cause: "window never appeared".to_string(),
            },
        });
        effects.push(Effect::WriteBrowserCache {
            ctx_slug: "scratch".to_string(),
            role: BrowserRole::Docs,
            id: None,
        });
    }
    if let Some(term) = term {
        if Some(term.workspace_id) != target_ws {
            effects.push(Effect::MoveWindowToWorkspace {
                id: term.id,
                ws: WorkspaceRef::name("scratch"),
                focus: false,
            });
        }
    } else {
        effects.push(Effect::SpawnTerminal {
            ctx: Context::UP,
            role: Role::Term,
            app_id: "dev.yiannis.niri.scratch.term".to_string(),
            title: "scratch".to_string(),
        });
        effects.push(Effect::WaitForWindow {
            matcher: WindowMatcher::AppIdExact("dev.yiannis.niri.scratch.term".to_string()),
            timeout: Duration::from_secs(cfg.behavior.launch_timeout_secs),
            on_fail: LaunchFailure {
                command: "terminal scratch".to_string(),
                app_id: "dev.yiannis.niri.scratch.term".to_string(),
                cause: "window never appeared".to_string(),
            },
        });
    }
    if let (Some(docs), Some(term)) = (docs, term) {
        effects.extend(flatten_pair_if_stacked(docs, term));
        effects.extend(ensure_column(docs, 1));
        effects.extend(ensure_column(term, 2));
        if !term.is_focused {
            effects.push(Effect::FocusWindow { id: term.id });
        }
    }
    Ok(effects)
}

fn plan_comms(cfg: &Config, state: &DesktopState) -> Result<Vec<Effect>> {
    let mut effects = Vec::new();
    let comms_ws = state
        .workspace_by_name("comms")
        .map(|workspace| workspace.id);
    let mut present = Vec::new();
    for app in &cfg.comms.apps {
        if let Some(window) = state.oldest_window_by_app_id(&app.app_id) {
            if Some(window.workspace_id) != comms_ws {
                effects.push(Effect::MoveWindowToWorkspace {
                    id: window.id,
                    ws: WorkspaceRef::name("comms"),
                    focus: false,
                });
            }
            if !window.is_floating && Some(window.workspace_id) == comms_ws {
                present.push((app, window));
            }
        } else {
            effects.push(Effect::SpawnCommsApp {
                app: app.name.clone(),
            });
            effects.push(Effect::WaitForWindow {
                matcher: WindowMatcher::AppIdExact(app.app_id.clone()),
                timeout: Duration::from_secs(cfg.behavior.launch_timeout_secs),
                on_fail: launch_fail(app),
            });
        }
    }
    effects.extend(focus_workspace_guarded(
        state,
        &cfg.outputs.vertical,
        "comms",
    ));
    if present.len() > 1 {
        effects.extend(arrange_comms(&present));
    }
    Ok(effects)
}

fn plan_spotify(cfg: &Config, state: &DesktopState) -> Result<Vec<Effect>> {
    let mut effects = Vec::new();
    let app_id = &cfg.ambient.spotify_app_id;
    let ambient_ws = state
        .workspace_by_name("top-ambient")
        .map(|workspace| workspace.id);
    if let Some(window) = state.oldest_window_by_app_id(app_id) {
        if Some(window.workspace_id) != ambient_ws {
            effects.push(Effect::MoveWindowToWorkspace {
                id: window.id,
                ws: WorkspaceRef::name("top-ambient"),
                focus: false,
            });
        }
        effects.extend(focus_workspace_guarded(
            state,
            &cfg.outputs.top,
            "top-ambient",
        ));
        if !window.is_focused {
            effects.push(Effect::FocusWindow { id: window.id });
        }
    } else {
        effects.push(Effect::SpawnSpotify);
        effects.push(Effect::WaitForWindow {
            matcher: WindowMatcher::AppIdExact(app_id.clone()),
            timeout: Duration::from_secs(20),
            on_fail: LaunchFailure {
                command: "spotify".to_string(),
                app_id: app_id.clone(),
                cause: "window never appeared".to_string(),
            },
        });
    }
    Ok(effects)
}

/// Bash top-ambient (bin/niri-ctx:1148-1151): guard-focus top-ambient on TOP,
/// then ALWAYS return focus to the main monitor (monitor only, no workspace
/// focus). When top-ambient is already showing on TOP we skip the pointless
/// TOP round-trip and only correct final focus if it isn't on main.
fn plan_top_ambient(cfg: &Config, state: &DesktopState) -> Vec<Effect> {
    let already_showing = state
        .active_workspace_name_on_output(&cfg.outputs.top)
        .is_some_and(|name| name.eq_ignore_ascii_case("top-ambient"));
    let mut effects = if already_showing {
        Vec::new()
    } else {
        let effects = focus_workspace_guarded(state, &cfg.outputs.top, "top-ambient");
        if effects.iter().any(|e| matches!(e, Effect::Fail { .. })) {
            return effects;
        }
        effects
    };
    let on_main = state.focused_output() == Some(cfg.outputs.main.as_str());
    if !effects.is_empty() || !on_main {
        effects.push(Effect::FocusOutput {
            output: cfg.outputs.main.clone(),
        });
    }
    effects
}

fn plan_devtools_here(cfg: &Config, state: &DesktopState) -> Result<Vec<Effect>> {
    let Some(focused_id) = state.focused_window else {
        return Ok(Vec::new());
    };
    let Some(window) = state.window(focused_id) else {
        return Ok(Vec::new());
    };
    let Some(workspace_name) = state
        .workspace(window.workspace_id)
        .and_then(|workspace| workspace.name.as_deref())
    else {
        return Ok(Vec::new());
    };
    let Some(ctx) = Context::from_workspace_name(workspace_name) else {
        return Ok(Vec::new());
    };
    if ctx == Context::Admin {
        return Ok(Vec::new());
    }
    let Some(devtools_ws) = ctx.devtools_workspace() else {
        return Ok(Vec::new());
    };
    let mut effects = Vec::new();
    if !workspace_name.eq_ignore_ascii_case(&devtools_ws) {
        effects.push(Effect::MoveWindowToWorkspace {
            id: focused_id,
            ws: WorkspaceRef::name(&devtools_ws),
            focus: false,
        });
    }
    effects.extend(focus_workspace_guarded(
        state,
        &cfg.outputs.top,
        &devtools_ws,
    ));
    effects.extend(focus_workspace_guarded(
        state,
        &cfg.outputs.main,
        ctx.name(),
    ));
    Ok(effects)
}

pub fn focus_workspace_guarded(state: &DesktopState, output: &str, workspace: &str) -> Vec<Effect> {
    let Some(target) = state.workspace_by_name(workspace) else {
        return vec![Effect::Fail {
            diag: format!("workspace {workspace} does not exist"),
        }];
    };
    if target.is_focused {
        return Vec::new();
    }
    let mut effects = Vec::new();
    if !state.output_is_focused(output) {
        effects.push(Effect::FocusOutput {
            output: output.to_string(),
        });
    }
    let active_matches = state
        .active_workspace_name_on_output(output)
        .is_some_and(|active| active.eq_ignore_ascii_case(workspace));
    if !active_matches {
        effects.push(Effect::FocusWorkspace {
            output: output.to_string(),
            ws: WorkspaceRef::name(workspace),
        });
    }
    effects
}

fn browser_window<'a>(
    state: &'a DesktopState,
    slug: &str,
    role: BrowserRole,
) -> Option<&'a Window> {
    state.cached_browser_window(slug, role)
}

fn work_window<'a>(
    cfg: &Config,
    state: &'a DesktopState,
    ctx: Context,
) -> Result<Option<&'a Window>> {
    let app_id = cfg.work_app_id(ctx)?;
    Ok(state.oldest_window_by_app_id(&app_id))
}

fn flatten_pair_if_stacked(left: &Window, right: &Window) -> Vec<Effect> {
    if left.workspace_id == right.workspace_id {
        if let (Some((left_col, left_row)), Some((right_col, right_row))) =
            (left.column, right.column)
        {
            if left_col == right_col {
                let id = if left_row >= right_row {
                    left.id
                } else {
                    right.id
                };
                return vec![Effect::FocusWindow { id }, Effect::ExpelWindowFromColumn];
            }
        }
    }
    Vec::new()
}

fn ensure_column(window: &Window, index: usize) -> Vec<Effect> {
    if window.column.map(|(column, _row)| column) == Some(index) {
        Vec::new()
    } else {
        vec![
            Effect::FocusWindow { id: window.id },
            Effect::MoveColumnToIndex { index },
        ]
    }
}

fn arrange_comms(present: &[(&CommsAppConfig, &Window)]) -> Vec<Effect> {
    let mut effects = Vec::new();
    let all_same_column = present
        .iter()
        .filter_map(|(_app, window)| window.column.map(|(column, _row)| column))
        .collect::<BTreeSet<_>>()
        .len()
        == 1;
    if all_same_column {
        // Bash reapplies equal heights on every comms run even when the stack
        // shape is already right. To stay convergent (empty plan when settled)
        // we only re-emit heights when the observed tile heights are unequal
        // beyond tolerance; app min-height constraints get best-effort
        // treatment in the converge loop rather than a hard failure.
        effects.extend(equalize_heights_if_unequal(present));
        if let Some((_app, first)) = present.first() {
            if !first.is_focused {
                effects.push(Effect::FocusWindow { id: first.id });
            }
        }
        return effects;
    }

    for (idx, (_app, window)) in present.iter().enumerate() {
        effects.extend(ensure_column(window, idx + 1));
    }
    if let Some((_app, first)) = present.first() {
        effects.push(Effect::FocusWindow { id: first.id });
        effects.push(Effect::SetColumnWidth {
            change: SizeChange::SetProportion(100.0),
        });
        for _ in present.iter().skip(1) {
            effects.push(Effect::ConsumeWindowIntoColumn);
        }
    }
    let height = 100.0 / present.len() as f64;
    for (_app, window) in present {
        effects.push(Effect::SetWindowHeight {
            id: window.id,
            change: SizeChange::SetProportion(height),
        });
    }
    effects
}

/// Emit SetWindowHeight for a settled comms stack whose tile heights drifted
/// apart (e.g. a manually resized window) by more than 5% relative spread.
fn equalize_heights_if_unequal(present: &[(&CommsAppConfig, &Window)]) -> Vec<Effect> {
    if present.len() < 2 {
        return Vec::new();
    }
    let heights: Vec<f64> = present
        .iter()
        .filter_map(|(_app, window)| window.tile_height)
        .collect();
    if heights.len() != present.len() {
        return Vec::new();
    }
    let max = heights.iter().cloned().fold(f64::MIN, f64::max);
    let min = heights.iter().cloned().fold(f64::MAX, f64::min);
    if max <= 0.0 || (max - min) / max <= 0.05 {
        return Vec::new();
    }
    let height = 100.0 / present.len() as f64;
    present
        .iter()
        .map(|(_app, window)| Effect::SetWindowHeight {
            id: window.id,
            change: SizeChange::SetProportion(height),
        })
        .collect()
}

fn launch_fail(app: &CommsAppConfig) -> LaunchFailure {
    LaunchFailure {
        command: app
            .launch
            .first()
            .map(|argv| argv.join(" "))
            .unwrap_or_else(|| app.name.clone()),
        app_id: app.app_id.clone(),
        cause: "window never appeared".to_string(),
    }
}

pub fn effect_to_json(effect: &Effect) -> serde_json::Value {
    match effect {
        Effect::SetColumnWidth { change } => {
            serde_json::json!({"SetColumnWidth": {"change": format!("{change:?}")}})
        }
        Effect::SetWindowHeight { id, change } => {
            serde_json::json!({"SetWindowHeight": {"id": id.0, "change": format!("{change:?}")}})
        }
        other => serde_json::json!(format!("{other:?}")),
    }
}

#[allow(dead_code)]
fn _kind_for_name(name: &str) -> Option<CommsAppKind> {
    match name {
        "slack" => Some(CommsAppKind::Slack),
        "telegram" => Some(CommsAppKind::Telegram),
        "discord" => Some(CommsAppKind::Discord),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::model::{WorkspaceId, WorkspaceRef};
    use crate::niri::Workspace;

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
        workspace_id: u64,
        focused: bool,
        column: Option<(usize, usize)>,
    ) -> Window {
        Window {
            id: WindowId(id),
            title: String::new(),
            app_id: app_id.to_string(),
            pid: 1,
            workspace_id: WorkspaceId(workspace_id),
            is_focused: focused,
            is_floating: false,
            column,
            tile_height: Some(500.0),
        }
    }

    fn base_workspaces() -> Vec<Workspace> {
        vec![
            ws(1, "UP", "DP-1", true, true),
            ws(2, "Webroot", "DP-1", false, false),
            ws(3, "Side", "DP-1", false, false),
            ws(4, "comms", "HDMI-A-1", true, false),
            ws(5, "top-ambient", "DP-2", true, false),
            ws(6, "Admin", "DP-1", false, false),
            ws(7, "scratch", "DP-1", false, false),
            ws(8, "UP-devtools", "DP-2", false, false),
        ]
    }

    #[test]
    fn focus_guard_empty_when_target_focused() {
        let state = DesktopState::new(base_workspaces(), vec![]);
        assert!(focus_workspace_guarded(&state, "DP-1", "UP").is_empty());
    }

    #[test]
    fn focus_guard_focuses_output_only_when_target_active_there() {
        let state = DesktopState::new(
            vec![
                ws(1, "UP", "DP-1", true, false),
                ws(5, "top-ambient", "DP-2", true, true),
            ],
            vec![],
        );
        assert_eq!(
            focus_workspace_guarded(&state, "DP-1", "UP"),
            vec![Effect::FocusOutput {
                output: "DP-1".to_string()
            }]
        );
    }

    #[test]
    fn focus_guard_focuses_workspace_only_when_output_already_focused() {
        let state = DesktopState::new(
            vec![
                ws(1, "UP", "DP-1", false, false),
                ws(3, "Side", "DP-1", true, true),
            ],
            vec![],
        );
        assert_eq!(
            focus_workspace_guarded(&state, "DP-1", "UP"),
            vec![Effect::FocusWorkspace {
                output: "DP-1".to_string(),
                ws: WorkspaceRef::name("UP")
            }]
        );
    }

    #[test]
    fn open_all_settled_is_empty() {
        let cfg = cfg();
        let state = DesktopState::new(
            base_workspaces(),
            vec![
                win(10, "helium", 1, true, Some((1, 0))),
                win(
                    20,
                    &cfg.work_app_id(Context::UP).expect("app id"),
                    1,
                    false,
                    Some((2, 0)),
                ),
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
        assert!(effects.is_empty(), "{effects:#?}");
    }

    #[test]
    fn open_all_from_other_context_emits_one_focus_workspace() {
        // Live regression: settled UP cards while Side is focused. The composed
        // plan (open-all focus + browser sub-plan + work sub-plan + refocus)
        // must collapse to ONE FocusWorkspace — executing duplicates would
        // bounce via workspace-auto-back-and-forth.
        let cfg = cfg();
        let mut workspaces = base_workspaces();
        for ws in &mut workspaces {
            let on_side = ws.name.as_deref() == Some("Side");
            if ws.output == "DP-1" {
                ws.is_active = on_side;
            }
            ws.is_focused = on_side;
        }
        let state = DesktopState::new(
            workspaces,
            vec![
                win(10, "helium", 1, false, Some((1, 0))),
                win(
                    20,
                    &cfg.work_app_id(Context::UP).expect("app id"),
                    1,
                    false,
                    Some((2, 0)),
                ),
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
        let focus_ws_count = effects
            .iter()
            .filter(|effect| matches!(effect, Effect::FocusWorkspace { .. }))
            .count();
        assert_eq!(focus_ws_count, 1, "{effects:#?}");
        assert_eq!(
            effects.last(),
            Some(&Effect::FocusWindow { id: WindowId(10) }),
            "{effects:#?}"
        );
    }

    #[test]
    fn open_all_rehomes_drifted_docs_and_work() {
        let cfg = cfg();
        let state = DesktopState::new(
            base_workspaces(),
            vec![
                win(10, "helium", 2, false, Some((1, 0))),
                win(
                    20,
                    &cfg.work_app_id(Context::UP).expect("app id"),
                    3,
                    false,
                    Some((2, 0)),
                ),
            ],
        )
        .with_browser_cache_entry("up", BrowserRole::Docs, WindowId(10));
        let effects = plan_open_all(&cfg, &state, Context::UP).expect("plan");
        assert!(effects.contains(&Effect::MoveWindowToWorkspace {
            id: WindowId(10),
            ws: WorkspaceRef::name("UP"),
            focus: false,
        }));
        assert!(effects.contains(&Effect::MoveWindowToWorkspace {
            id: WindowId(20),
            ws: WorkspaceRef::name("UP"),
            focus: false,
        }));
    }

    #[test]
    fn open_all_repairs_stacked_cards_with_focused_expel() {
        let cfg = cfg();
        let state = DesktopState::new(
            base_workspaces(),
            vec![
                win(10, "helium", 1, false, Some((1, 0))),
                win(
                    20,
                    &cfg.work_app_id(Context::UP).expect("app id"),
                    1,
                    true,
                    Some((1, 1)),
                ),
            ],
        )
        .with_browser_cache_entry("up", BrowserRole::Docs, WindowId(10));
        let effects = plan_open_all(&cfg, &state, Context::UP).expect("plan");
        assert_eq!(effects[0], Effect::FocusWindow { id: WindowId(20) });
        assert_eq!(effects[1], Effect::ExpelWindowFromColumn);
    }

    #[test]
    fn open_all_missing_cards_spawns_and_waits() {
        let cfg = cfg();
        let state = DesktopState::new(base_workspaces(), vec![]);
        let effects = plan_open_all(&cfg, &state, Context::UP).expect("plan");
        assert!(effects
            .iter()
            .any(|effect| matches!(effect, Effect::SpawnBrowser { .. })));
        assert!(effects
            .iter()
            .any(|effect| matches!(effect, Effect::SpawnTerminal { .. })));
        assert_eq!(
            effects
                .iter()
                .filter(|effect| matches!(effect, Effect::WaitForWindow { .. }))
                .count(),
            2
        );
    }

    #[test]
    fn comms_settled_is_empty() {
        let cfg = cfg();
        let state = DesktopState::new(
            vec![
                ws(1, "UP", "DP-1", true, false),
                ws(4, "comms", "HDMI-A-1", true, true),
            ],
            vec![
                win(10, "slack", 4, true, Some((1, 0))),
                win(11, "org.telegram.desktop", 4, false, Some((1, 1))),
                win(12, "discord", 4, false, Some((1, 2))),
            ],
        );
        let effects = plan(&cfg, &state, &Goal::Comms).expect("plan");
        assert!(effects.is_empty(), "{effects:#?}");
    }

    #[test]
    fn spotify_settled_is_empty() {
        let cfg = cfg();
        let state = DesktopState::new(
            vec![ws(5, "top-ambient", "DP-2", true, true)],
            vec![win(30, "Spotify", 5, true, Some((1, 0)))],
        );
        let effects = plan(&cfg, &state, &Goal::Spotify).expect("plan");
        assert!(effects.is_empty(), "{effects:#?}");
    }

    #[test]
    fn scratch_settled_is_empty() {
        let cfg = cfg();
        let state = DesktopState::new(
            vec![ws(7, "scratch", "DP-1", true, true)],
            vec![
                win(10, "helium", 7, false, Some((1, 0))),
                win(11, "dev.yiannis.niri.scratch.term", 7, true, Some((2, 0))),
            ],
        )
        .with_browser_cache_entry("scratch", BrowserRole::Docs, WindowId(10));
        let effects = plan(&cfg, &state, &Goal::Scratch).expect("plan");
        assert!(effects.is_empty(), "{effects:#?}");
    }

    #[test]
    fn top_ambient_settled_is_empty() {
        // top-ambient already showing on DP-2, focus already on main.
        let cfg = cfg();
        let state = DesktopState::new(base_workspaces(), vec![]);
        let effects = plan(&cfg, &state, &Goal::TopAmbient).expect("plan");
        assert!(effects.is_empty(), "{effects:#?}");
    }

    #[test]
    fn top_ambient_switches_top_and_returns_focus_to_main() {
        // UP-devtools showing on DP-2: switch DP-2 to top-ambient, then Bash
        // parity requires focus to come back to the main monitor.
        let cfg = cfg();
        let mut workspaces = base_workspaces();
        for ws in &mut workspaces {
            if ws.output == "DP-2" {
                ws.is_active = ws.name.as_deref() == Some("UP-devtools");
            }
        }
        let state = DesktopState::new(workspaces, vec![]);
        let effects = plan(&cfg, &state, &Goal::TopAmbient).expect("plan");
        assert_eq!(
            effects,
            vec![
                Effect::FocusOutput {
                    output: "DP-2".to_string(),
                },
                Effect::FocusWorkspace {
                    output: "DP-2".to_string(),
                    ws: WorkspaceRef::name("top-ambient"),
                },
                Effect::FocusOutput {
                    output: "DP-1".to_string(),
                },
            ],
            "{effects:#?}"
        );
    }

    #[test]
    fn comms_stacked_but_unequal_heights_reequalizes() {
        let cfg = cfg();
        let mut windows = vec![
            win(8, "org.telegram.desktop", 4, false, Some((1, 2))),
            win(10, "slack", 4, false, Some((1, 1))),
            win(11, "discord", 4, true, Some((1, 3))),
        ];
        // slack manually resized much taller than the others
        for window in &mut windows {
            window.tile_height = Some(if window.app_id == "slack" {
                900.0
            } else {
                300.0
            });
        }
        let state = DesktopState::new(comms_focused_workspaces(), windows);
        let effects = plan(&cfg, &state, &Goal::Comms).expect("plan");
        let heights = effects
            .iter()
            .filter(|effect| matches!(effect, Effect::SetWindowHeight { .. }))
            .count();
        assert_eq!(heights, 3, "{effects:#?}");

        // equal heights => settled, no plan
        let mut windows = vec![
            win(8, "org.telegram.desktop", 4, false, Some((1, 2))),
            win(10, "slack", 4, true, Some((1, 1))),
            win(11, "discord", 4, false, Some((1, 3))),
        ];
        for window in &mut windows {
            window.tile_height = Some(480.0);
        }
        let state = DesktopState::new(comms_focused_workspaces(), windows);
        let effects = plan(&cfg, &state, &Goal::Comms).expect("plan");
        assert!(effects.is_empty(), "{effects:#?}");
    }

    fn comms_focused_workspaces() -> Vec<Workspace> {
        vec![
            ws(1, "UP", "DP-1", true, false),
            ws(4, "comms", "HDMI-A-1", true, true),
        ]
    }

    #[test]
    fn devtools_here_admin_noops() {
        let cfg = cfg();
        let state = DesktopState::new(
            vec![ws(6, "Admin", "DP-1", true, true)],
            vec![win(40, "helium", 6, true, Some((1, 0)))],
        );
        let effects = plan(&cfg, &state, &Goal::DevtoolsHere).expect("plan");
        assert!(effects.is_empty(), "{effects:#?}");
    }
}
