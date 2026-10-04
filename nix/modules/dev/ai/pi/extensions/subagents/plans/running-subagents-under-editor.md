# Plan: running subagents below the prompt editor

## Context

The extension currently exposes subagent activity through a footer status and the `/subagents` fullscreen picker/takeover UI. The requested change is to keep currently running subagents visible immediately below the prompt editor and make their histories navigable from the keyboard without first opening `/subagents`.

Feasibility is confirmed. Pi supports a persistent custom component below the editor through `ctx.ui.setWidget(..., { placement: "belowEditor" })`, and its custom-editor API can intercept navigation only while the real prompt editor has focus. The extension already has the live snapshot data needed for the pane, including a required spawn `name` stored as `snapshot.title`, streamed/finalized thinking, context occupancy/window, backend (harness), and model label.

## Approach

- Add one reactive compact row per currently running, model-origin (`sa-*`) subagent below the editor; settled/cancelled agents and `btw-*` sessions are excluded.
- Show the existing spawn title/name, id, harness/model, context occupancy/window, and only the newest non-empty reasoning paragraph/markdown step.
- Keep the pane unfocused initially so Up remains prompt-history navigation. With an exactly empty editor, one Down press focuses the current row without moving it.
- While focused, render the selected child's history in a reactive above-editor pane that pushes the teamlead transcript out of view without covering the prompt, compact rows, status, usage, or footer. Use Pi's exported user, assistant, and tool components, and accent only the prompt border.
- Use Down to advance and Up to move toward the first agent; Up on the first row or Escape closes the view. Leave Left unclaimed for the background-task extension. PageUp/PageDown scrolls. Typing remains active and Enter prompts the selected child.
- Implement keyboard handling compositionally by decorating the same prior editor instance, preserving focus/IME, callbacks, autocomplete, text/history, app-action hooks, and earlier custom-editor behavior. Accent the prompt border and hide the teamlead `Working...` row only while focused.
- Keep `/subagents` unchanged as the separate dashboard/takeover experience.

## Files to modify

- `index.ts` — install the compact pane, non-capturing history replacement, and editor decorator with session lifecycle cleanup.
- `src/ui/running-subagents.ts` (new) — filtering, selection/focus/scroll state, compact rows, replacement history overlay, and editor decorator.
- `running-subagents.test.ts` (new) — filtering, selection, thinking, rendering, overlay, history restoration, and key-routing tests.
- `package.json` — include the focused test file in `npm test`.
- `docs/design-plan.md` — document compact rows and replacement-history behavior.

## Reuse

- `SubagentReadModel.list()` and `subscribe()` in `src/manager.ts` provide synchronous snapshots and change notifications; thinking deltas and usage changes already trigger those notifications.
- `SubagentSnapshot.liveAssistant`, `transcript`, `usage`, `meta.modelLabel`, `backend`, and `title` in `src/domain.ts` contain all display data; no manager/backend/domain expansion is needed.
- `sanitizeText()` in `src/ui/transcript.ts` can be reused before collapsing the latest thinking to one terminal-safe line.
- `contextPercent()` and `formatCompactTokens()` in `src/format.ts` can format occupancy and window size without duplicating token logic.
- `ctx.ui.setWidget(id, factory, { placement: "belowEditor" })` supplies the supported placement and a `tui` handle for reactive rerenders; the component's `dispose()` can unsubscribe from the read model.
- `ctx.ui.getEditorComponent()` / `setEditorComponent()` and `CustomEditor` are Pi's supported composition path. Pi's `EditorComponent` contract exposes the text, callback, history, autocomplete, and focus-related surface that the decorator must preserve.
- `reconcileDashboardSelection()` in `src/ui/takeover.ts` provides the stable-id/fallback-index pattern; the compact pane will use the same behavior but filter to eligible running snapshots first.

## Steps

- [x] Add helpers for eligible running-agent filtering, explicit focus/scroll state, stable wraparound selection, and newest-step reasoning extraction.
- [x] Build a disposable, width-bounded compact row component that renders zero lines when no eligible child runs.
- [x] Build a reactive above-editor history pane that preserves the full bottom dock and renders child history with Pi's normal message/tool components.
- [x] Add compositional editor routing: Down focuses/advances, Up navigates back or exits from the first row, Escape exits, PageUp/PageDown scrolls, Left remains unclaimed, and Enter prompts the selected child.
- [x] Preserve restored prompt history and prior custom-editor behavior across startup/reload/session replacement.
- [x] Add focused tests for filtering, selection, reasoning, width safety, overlay behavior, restored history, focus, scrolling, and delegation.
- [x] Document the final interaction and run automated regression checks.

## Verification

- Baseline before implementation: `npm test` passes 47/47 and `npm run check` passes.
- After callback-enabled background lifecycle tracking: `npm test` passes 65/65, `npm run check` passes, and `git diff --check` passes.
- Manually launch Pi with the extension, spawn multiple concurrent subagents, and verify:
  - only running `sa-*` agents appear as compact metadata/latest-thinking rows;
  - before focus, Up still browses prompt history; Down focuses the first/current child without moving it;
  - focus visually replaces the teamlead transcript while preserving the prompt, compact rows, status, usage, and footer;
  - Up/Down changes the selected child and PageUp/PageDown scrolls that child's history;
  - Up on the first row or Escape closes the replacement; Left remains available to background tasks; typing stays in the child view and Enter prompts the selected subagent;
  - multi-paragraph or consecutive markdown thinking steps show only the newest compact step;
  - live thinking and context updates repaint without stealing terminal focus or changing editor text;
  - selection remains on the same id when possible and falls back predictably when the selected agent settles/cancels;
  - narrow terminals truncate every line safely;
  - an existing custom editor remains functional beneath the decorator;
  - `/subagents`, takeover scrolling/input, footer status, reload, and shutdown continue to work.
