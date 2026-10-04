/**
 * Takeover UI for subagents (ported from v1, rendering from the synchronous
 * recursive SubagentTreeView instead of live pi sessions):
 * - SubagentDashboard: full popup (overlay) listing all subagents.
 * - TakeoverView: full interactive view of one subagent with an input line
 *   to steer/continue it.
 */

import type {
  ExtensionCommandContext,
  KeybindingsManager,
  Theme,
} from "@earendil-works/pi-coding-agent";
import type { Component, Focusable, TUI } from "@earendil-works/pi-tui";
import { Input, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { formatElapsed, type SubagentSnapshot } from "../domain.ts";
import { formatContextUtilization } from "../format.ts";
import {
  subagentTreePrefix,
  type SubagentTreeNode,
  type SubagentTreeView,
} from "../subagent-tree.ts";
import { buildTranscriptLines } from "./transcript.ts";

function configuredKeys(
  keybindings: KeybindingsManager,
  binding: Parameters<KeybindingsManager["getKeys"]>[0],
) {
  return keybindings.getKeys(binding).join("/") || "unbound";
}

function statusGlyph(snap: SubagentSnapshot, theme: Theme): string {
  switch (snap.status) {
    case "running":
      return theme.fg("warning", "■");
    case "done":
      return theme.fg("success", "■");
    case "error":
      return theme.fg("error", "■");
  }
}

function statusWord(snap: SubagentSnapshot, theme: Theme): string {
  switch (snap.status) {
    case "running":
      return theme.fg("warning", "running");
    case "done":
      return theme.fg("success", "done");
    case "error":
      return theme.fg("error", "failed");
  }
}

export function renderDashboardTreeRow(
  node: SubagentTreeNode,
  isSelected: boolean,
  width: number,
  theme: Theme,
): string {
  const snap = node.snapshot;
  const marker = isSelected ? theme.fg("accent", "❯") : " ";
  const title = isSelected
    ? theme.fg("accent", snap.title)
    : theme.fg("text", snap.title);
  const replyBadge =
    snap.pendingQuestions.length > 0
      ? ` ${theme.fg("warning", `?${snap.pendingQuestions.length}`)}`
      : "";
  const left =
    ` ${marker} ${theme.fg("dim", subagentTreePrefix(node))}` +
    `${statusGlyph(snap, theme)} ${title} ${theme.fg("dim", snap.id)}${replyBadge}`;

  const utilization = formatContextUtilization(snap.usage);
  const dot = theme.fg("dim", " · ");
  const rightParts = [
    theme.fg("muted", snap.backend),
    theme.fg("muted", snap.meta.modelLabel ?? "?"),
    ...(utilization ? [theme.fg("muted", utilization)] : []),
    theme.fg("muted", formatElapsed(snap)),
    statusWord(snap, theme),
  ];
  const right = `${rightParts.join(dot)} `;
  const rightWidth = visibleWidth(right);
  const leftMax = Math.max(0, width - rightWidth - 2);
  const leftTruncated = truncateToWidth(left, leftMax);
  const gap = Math.max(2, width - visibleWidth(leftTruncated) - rightWidth);
  return truncateToWidth(leftTruncated + " ".repeat(gap) + right, width);
}

// --- Entry points --------------------------------------------------------------

export interface TakeoverOptions {
  readonly badge?: string;
}

export async function openSubagentTakeover(
  ctx: ExtensionCommandContext,
  view: SubagentTreeView,
  key: string,
  options?: TakeoverOptions,
) {
  if (!view.get(key)) return;
  await ctx.ui.custom<null>(
    (tui, theme, keybindings, done) =>
      new TakeoverView(tui, theme, keybindings, key, view, done, options),
    {
      overlay: true,
      overlayOptions: { anchor: "center", width: "100%", maxHeight: "100%" },
    },
  );
}

export async function openSubagentPicker(
  ctx: ExtensionCommandContext,
  view: SubagentTreeView,
) {
  const selection: DashboardSelection = { index: 0 };

  while (true) {
    if (view.size() === 0) {
      ctx.ui.notify("No subagents", "info");
      return;
    }

    const picked = await ctx.ui.custom<string | null>(
      (tui, theme, keybindings, done) =>
        new SubagentDashboard(tui, theme, keybindings, view, selection, done),
      {
        overlay: true,
        overlayOptions: { anchor: "center", width: "100%", maxHeight: "100%" },
      },
    );

    if (!picked) return;
    if (!view.get(picked)) continue;

    await openSubagentTakeover(ctx, view, picked);
    // After leaving the takeover view, fall back to the dashboard.
  }
}

// --- Dashboard (fullscreen overlay) ----------------------------------------------

export interface DashboardSelection {
  key?: string;
  index: number;
}

export function reconcileDashboardSelection(
  selection: DashboardSelection,
  nodes: ReadonlyArray<Pick<SubagentTreeNode, "key">>,
) {
  const stableIndex = selection.key
    ? nodes.findIndex((node) => node.key === selection.key)
    : -1;
  selection.index =
    stableIndex >= 0
      ? stableIndex
      : Math.min(Math.max(0, selection.index), Math.max(0, nodes.length - 1));
  selection.key = nodes[selection.index]?.key;
}

class SubagentDashboard implements Component {
  private tui: TUI;
  private theme: Theme;
  private keybindings: KeybindingsManager;
  private view: SubagentTreeView;
  private selection: DashboardSelection;
  private done: (value: string | null) => void;

  private closed = false;
  private ticker: ReturnType<typeof setInterval>;
  private unsubChange: () => void;

  constructor(
    tui: TUI,
    theme: Theme,
    keybindings: KeybindingsManager,
    view: SubagentTreeView,
    selection: DashboardSelection,
    done: (value: string | null) => void,
  ) {
    this.tui = tui;
    this.theme = theme;
    this.keybindings = keybindings;
    this.view = view;
    this.selection = selection;
    this.done = done;
    // Elapsed times, token counts, and statuses tick along at 1Hz.
    this.ticker = setInterval(() => this.tui.requestRender(), 1000);
    this.unsubChange = view.subscribe(() => this.tui.requestRender());
  }

  private nodes(): ReadonlyArray<SubagentTreeNode> {
    return this.view.list();
  }

  private cleanup() {
    if (this.closed) return false;
    this.closed = true;
    clearInterval(this.ticker);
    this.unsubChange();
    return true;
  }

  private close(result: string | null) {
    if (this.cleanup()) this.done(result);
  }

  dispose(): void {
    this.cleanup();
  }

  handleInput(data: string): void {
    const nodes = this.nodes();
    reconcileDashboardSelection(this.selection, nodes);

    if (this.keybindings.matches(data, "tui.select.cancel")) {
      this.close(null);
      return;
    }
    if (this.keybindings.matches(data, "tui.select.confirm")) {
      const node = nodes[this.selection.index];
      if (node) this.close(node.key);
      return;
    }
    if (this.keybindings.matches(data, "tui.select.up") || data === "k") {
      if (nodes.length > 0) {
        this.selection.index =
          (this.selection.index - 1 + nodes.length) % nodes.length;
        this.selection.key = nodes[this.selection.index]?.key;
        this.tui.requestRender();
      }
      return;
    }
    if (this.keybindings.matches(data, "tui.select.down") || data === "j") {
      if (nodes.length > 0) {
        this.selection.index = (this.selection.index + 1) % nodes.length;
        this.selection.key = nodes[this.selection.index]?.key;
        this.tui.requestRender();
      }
      return;
    }
    if (data === "x") {
      const node = nodes[this.selection.index];
      if (node?.snapshot.status === "running") {
        this.view.requestAbort(node.key);
      }
      return;
    }
  }

  private pad(text: string, width: number): string {
    const truncated = truncateToWidth(text, width);
    return truncated + " ".repeat(Math.max(0, width - visibleWidth(truncated)));
  }

  private borderSegment(width: number, title: string): string {
    const theme = this.theme;
    const label = title
      ? ` ${truncateToWidth(title, Math.max(0, width - 3))} `
      : "";
    const labelWidth = visibleWidth(label);
    return (
      theme.fg("border", "─") +
      (label ? theme.fg("text", label) : "") +
      theme.fg("border", "─".repeat(Math.max(0, width - 1 - labelWidth)))
    );
  }

  render(width: number): string[] {
    const theme = this.theme;
    const nodes = this.nodes();
    reconcileDashboardSelection(this.selection, nodes);

    const rows = this.tui.terminal.rows || 30;
    // Render exactly terminal rows - 1 so the overlay covers the header,
    // chat, editor, and extra footer lines while leaving pi's final footer
    // row visible.
    const bodyHeight = Math.max(6, rows - 5);
    const innerWidth = width - 2;

    const lines: string[] = [];

    // Header: title left, count right
    const headerLeft = theme.fg("accent", theme.bold("Subagents"));
    const headerRight = theme.fg(
      "muted",
      `${nodes.length} agent${nodes.length === 1 ? "" : "s"}`,
    );
    const headerPad = Math.max(
      1,
      width - visibleWidth(headerLeft) - visibleWidth(headerRight) - 4,
    );
    lines.push(
      truncateToWidth(
        `  ${headerLeft}${" ".repeat(headerPad)}${headerRight}  `,
        width,
      ),
    );

    // Top border with panel title
    const settled = nodes.filter(
      (node) => node.snapshot.status !== "running",
    ).length;
    lines.push(
      theme.fg("border", "╭") +
        this.borderSegment(innerWidth, `tree · ${settled}/${nodes.length} settled`) +
        theme.fg("border", "╮"),
    );

    // Rows
    const divider = theme.fg("border", "│");
    const rowLines = this.renderRows(nodes, innerWidth, bodyHeight);
    for (let i = 0; i < bodyHeight; i++) {
      lines.push(divider + this.pad(rowLines[i] ?? "", innerWidth) + divider);
    }

    // Bottom border
    lines.push(
      theme.fg("border", "╰") +
        theme.fg("border", "─".repeat(innerWidth)) +
        theme.fg("border", "╯"),
    );

    // Hints
    lines.push(
      truncateToWidth(
        theme.fg(
          "dim",
          `  ${configuredKeys(this.keybindings, "tui.select.up")}/${configuredKeys(this.keybindings, "tui.select.down")}/jk select · ${configuredKeys(this.keybindings, "tui.select.confirm")} take over · x abort · ${configuredKeys(this.keybindings, "tui.select.cancel")} close`,
        ),
        width,
      ),
    );

    return lines;
  }

  private renderRows(
    nodes: ReadonlyArray<SubagentTreeNode>,
    width: number,
    height: number,
  ): string[] {
    const theme = this.theme;
    const out: string[] = [];

    // Scroll window around selection
    let start = 0;
    if (nodes.length > height) {
      start = Math.min(
        Math.max(0, this.selection.index - Math.floor(height / 2)),
        nodes.length - height,
      );
    }
    const visible = nodes.slice(start, start + height);

    for (let i = 0; i < visible.length; i++) {
      const index = start + i;
      out.push(
        renderDashboardTreeRow(
          visible[i],
          index === this.selection.index,
          width,
          theme,
        ),
      );
    }

    if (start > 0) {
      out[0] = truncateToWidth(theme.fg("dim", `   ... ${start} more`), width);
    }
    if (start + height < nodes.length) {
      out[out.length - 1] = truncateToWidth(
        theme.fg("dim", `   ... ${nodes.length - start - height} more`),
        width,
      );
    }
    return out;
  }

  invalidate(): void {}
}

// --- Takeover view ------------------------------------------------------------

const TRANSCRIPT_SCROLL_STEP = 6;

class TakeoverView implements Component, Focusable {
  private tui: TUI;
  private theme: Theme;
  private keybindings: KeybindingsManager;
  private key: string;
  private view: SubagentTreeView;
  private done: (value: null) => void;
  private options?: TakeoverOptions;

  private input = new Input();
  /** Scroll offset in lines from the bottom of the transcript. 0 = pinned to bottom. */
  private scrollOffset = 0;
  private unsubscribe: () => void;
  private renderTimer?: ReturnType<typeof setTimeout>;
  private ticker: ReturnType<typeof setInterval>;
  private closed = false;

  private _focused = false;
  get focused(): boolean {
    return this._focused;
  }
  set focused(value: boolean) {
    this._focused = value;
    this.input.focused = value;
  }

  constructor(
    tui: TUI,
    theme: Theme,
    keybindings: KeybindingsManager,
    key: string,
    view: SubagentTreeView,
    done: (value: null) => void,
    options?: TakeoverOptions,
  ) {
    this.tui = tui;
    this.theme = theme;
    this.keybindings = keybindings;
    this.key = key;
    this.view = view;
    this.done = done;
    this.options = options;
    this.unsubscribe = view.subscribeTo(key, () => this.scheduleRender());
    // Elapsed time in the header ticks along at 1Hz.
    this.ticker = setInterval(() => this.tui.requestRender(), 1000);
    this.input.onSubmit = (value: string) => {
      const text = value.trim();
      if (!text) return;
      this.input.setValue("");
      this.view.requestSend(this.key, text);
      this.scrollOffset = 0;
      this.tui.requestRender();
    };
  }

  private node(): SubagentTreeNode | undefined {
    return this.view.get(this.key);
  }

  private scheduleRender() {
    if (this.renderTimer) return;
    // Streaming can emit an event per token. Limit terminal repaints so this
    // view cannot starve input handling or make the child look frozen.
    this.renderTimer = setTimeout(() => {
      this.renderTimer = undefined;
      if (!this.closed) this.tui.requestRender();
    }, 50);
  }

  private cleanup() {
    if (this.closed) return false;
    this.closed = true;
    this.unsubscribe();
    clearInterval(this.ticker);
    if (this.renderTimer) clearTimeout(this.renderTimer);
    this.renderTimer = undefined;
    return true;
  }

  private close() {
    if (this.cleanup()) this.done(null);
  }

  dispose(): void {
    this.cleanup();
  }

  handleInput(data: string): void {
    if (this.keybindings.matches(data, "app.clear")) {
      const node = this.node();
      if (node?.snapshot.status === "running") {
        this.view.requestAbort(this.key);
      }
      return;
    }
    if (
      this.keybindings.matches(data, "app.interrupt") ||
      this.keybindings.matches(data, "tui.select.cancel")
    ) {
      this.close();
      return;
    }
    if (this.keybindings.matches(data, "tui.editor.cursorUp")) {
      this.scrollOffset += TRANSCRIPT_SCROLL_STEP;
      this.tui.requestRender();
      return;
    }
    if (this.keybindings.matches(data, "tui.editor.cursorDown")) {
      this.scrollOffset = Math.max(
        0,
        this.scrollOffset - TRANSCRIPT_SCROLL_STEP,
      );
      this.tui.requestRender();
      return;
    }
    if (this.keybindings.matches(data, "tui.editor.pageUp")) {
      this.scrollOffset += this.viewportHeight();
      this.tui.requestRender();
      return;
    }
    if (this.keybindings.matches(data, "tui.editor.pageDown")) {
      this.scrollOffset = Math.max(
        0,
        this.scrollOffset - this.viewportHeight(),
      );
      this.tui.requestRender();
      return;
    }
    this.input.handleInput(data);
    this.tui.requestRender();
  }

  private viewportHeight(): number {
    const rows = this.tui.terminal.rows || 30;
    // The complete view renders viewport + 7 chrome rows. Using rows - 8
    // makes the overlay exactly terminal rows - 1.
    return Math.max(6, rows - 8);
  }

  render(width: number): string[] {
    const theme = this.theme;
    const border = theme.fg("borderAccent", "─".repeat(Math.max(1, width)));
    const lines: string[] = [];
    const node = this.node();
    const snap = node?.snapshot;

    if (!node || !snap) {
      lines.push(border);
      lines.push(theme.fg("dim", "subagent is no longer tracked"));
      lines.push(border);
      return lines;
    }

    lines.push(border);
    const utilization = formatContextUtilization(snap.usage);
    const header =
      `${statusGlyph(snap, theme)} ` +
      theme.fg(
        "accent",
        theme.bold(`${node.idPath.join(" › ")} · ${snap.title}`),
      ) +
      theme.fg(
        "muted",
        ` · ${snap.status} · run ${snap.run} · ${formatElapsed(snap)}`,
      ) +
      (snap.pendingQuestions.length > 0
        ? theme.fg(
            "warning",
            ` · ? ${snap.pendingQuestions.length} awaiting reply`,
          )
        : "") +
      (this.options?.badge
        ? theme.fg("muted", ` · ${this.options.badge}`)
        : "") +
      theme.fg("dim", ` · ${snap.backend}: ${snap.meta.modelLabel ?? "?"}`) +
      (utilization ? theme.fg("dim", ` · ${utilization}`) : "");
    lines.push(truncateToWidth(header, width));
    lines.push(border);

    // Fixed-height transcript viewport. Error and scroll status consume rows
    // inside the viewport so streaming/scrolling never changes overlay height.
    const transcript = buildTranscriptLines(snap, width, theme);
    const viewport = this.viewportHeight();
    const errorRows = snap.errorText ? 1 : 0;
    const scrollRows = this.scrollOffset > 0 ? 1 : 0;
    const transcriptCapacity = Math.max(1, viewport - errorRows - scrollRows);
    const maxOffset = Math.max(0, transcript.length - transcriptCapacity);
    if (this.scrollOffset > maxOffset) this.scrollOffset = maxOffset;

    const body: string[] = [];
    if (snap.errorText) {
      body.push(
        truncateToWidth(theme.fg("error", `error: ${snap.errorText}`), width),
      );
    }

    const capacity = Math.max(
      1,
      viewport - body.length - (this.scrollOffset > 0 ? 1 : 0),
    );
    const end = transcript.length - this.scrollOffset;
    const visible = transcript.slice(Math.max(0, end - capacity), end);
    if (visible.length === 0) body.push(theme.fg("dim", "(no output yet)"));
    else body.push(...visible);

    if (this.scrollOffset > 0) {
      body.push(
        truncateToWidth(
          theme.fg("dim", `... ${this.scrollOffset} lines below · ↓/pgdn`),
          width,
        ),
      );
    }
    while (body.length < viewport) body.push("");
    lines.push(...body.slice(0, viewport));

    lines.push(border);
    lines.push(...this.input.render(width));
    lines.push(
      truncateToWidth(
        theme.fg(
          "dim",
          `${configuredKeys(this.keybindings, "tui.input.submit")} send · ${configuredKeys(this.keybindings, "app.interrupt")} back · ${configuredKeys(this.keybindings, "app.clear")} abort run · ${configuredKeys(this.keybindings, "tui.editor.cursorUp")}/${configuredKeys(this.keybindings, "tui.editor.cursorDown")} scroll · ${configuredKeys(this.keybindings, "tui.editor.pageUp")}/${configuredKeys(this.keybindings, "tui.editor.pageDown")} page`,
        ),
        width,
      ),
    );
    lines.push(border);
    return lines;
  }

  invalidate(): void {
    this.input.invalidate();
  }
}
