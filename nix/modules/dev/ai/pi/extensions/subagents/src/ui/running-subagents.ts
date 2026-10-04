import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
  AssistantMessageComponent,
  CustomEditor,
  getMarkdownTheme,
  ToolExecutionComponent,
  UserMessageComponent,
  type ExtensionUIContext,
  type SessionEntry,
  type Theme,
} from "@earendil-works/pi-coding-agent";
import {
  Container,
  Key,
  matchesKey,
  Spacer,
  truncateToWidth,
  visibleWidth,
  type Component,
  type EditorComponent,
  type TUI,
} from "@earendil-works/pi-tui";
import type { SubagentSnapshot, TranscriptPart } from "../domain.ts";
import { contextPercent, formatCompactTokens } from "../format.ts";
import {
  subagentTreePrefix,
  type SubagentTreeNode,
  type SubagentTreeView,
} from "../subagent-tree.ts";
import { renderCommunicationCard } from "./communication.ts";
import { sanitizeText } from "./transcript.ts";

export const RUNNING_SUBAGENTS_WIDGET_KEY = "subagents-running";
export const RUNNING_SUBAGENTS_HISTORY_WIDGET_KEY = "subagents-history";
const RENDER_THROTTLE_MS = 50;
type EditorFactory = NonNullable<
  ReturnType<ExtensionUIContext["getEditorComponent"]>
>;

export interface RunningSelection {
  key?: string;
  index: number;
}

/** Rebuild the same user-message history Pi populates on session restore. */
export function sessionPromptHistory(
  entries: ReadonlyArray<SessionEntry>,
): string[] {
  const history: string[] = [];
  for (const entry of entries) {
    if (entry.type !== "message" || entry.message.role !== "user") continue;
    const content = entry.message.content;
    const text =
      typeof content === "string"
        ? content
        : content
            .filter(
              (part): part is { type: "text"; text: string } =>
                part.type === "text" && typeof part.text === "string",
            )
            .map((part) => part.text)
            .join("");
    if (text) history.push(text);
  }
  return history;
}

export function runningModelSubagents(
  snapshots: ReadonlyArray<SubagentSnapshot>,
): ReadonlyArray<SubagentSnapshot> {
  return snapshots.filter(
    (snapshot) => snapshot.origin === "model" && snapshot.status === "running",
  );
}

export function reconcileRunningSelection(
  selection: RunningSelection,
  nodes: ReadonlyArray<Pick<SubagentTreeNode, "key">>,
): void {
  const stableIndex = selection.key
    ? nodes.findIndex((node) => node.key === selection.key)
    : -1;
  selection.index =
    stableIndex >= 0
      ? stableIndex
      : Math.min(
          Math.max(0, selection.index),
          Math.max(0, nodes.length - 1),
        );
  selection.key = nodes[selection.index]?.key;
}

export class RunningSubagentController {
  readonly selection: RunningSelection = { index: 0 };
  private readonly view: SubagentTreeView;
  private focusedState = false;
  private onFocusChange?: (focused: boolean) => void;
  private historyScrollOffsetState = 0;
  private historyPageSize = 6;

  constructor(view: SubagentTreeView) {
    this.view = view;
  }

  get focused(): boolean {
    return this.focusedState;
  }

  get historyScrollOffset(): number {
    return this.historyScrollOffsetState;
  }

  nodes(): ReadonlyArray<SubagentTreeNode> {
    const nodes = this.view.list({ runningOnly: true, modelOnly: true });
    reconcileRunningSelection(this.selection, nodes);
    if (nodes.length === 0 && this.focusedState) this.unfocus();
    return nodes;
  }

  selectedNode(): SubagentTreeNode | undefined {
    return this.nodes()[this.selection.index];
  }

  selected(): SubagentSnapshot | undefined {
    return this.selectedNode()?.snapshot;
  }

  count(): number {
    return this.nodes().length;
  }

  setOnFocusChange(listener: ((focused: boolean) => void) | undefined): void {
    this.onFocusChange = listener;
  }

  focus(): boolean {
    if (this.count() === 0) return false;
    if (!this.focusedState) {
      this.focusedState = true;
      this.onFocusChange?.(true);
    }
    this.historyScrollOffsetState = 0;
    return true;
  }

  unfocus(): boolean {
    if (!this.focusedState) return false;
    this.focusedState = false;
    this.onFocusChange?.(false);
    return true;
  }

  select(key: string): boolean {
    const nodes = this.nodes();
    const index = nodes.findIndex((node) => node.key === key);
    if (index < 0) return false;
    this.selection.index = index;
    this.selection.key = key;
    this.historyScrollOffsetState = 0;
    return true;
  }

  move(delta: -1 | 1): boolean {
    const nodes = this.nodes();
    if (nodes.length < 2) return false;
    this.selection.index =
      (this.selection.index + delta + nodes.length) % nodes.length;
    this.selection.key = nodes[this.selection.index]?.key;
    this.historyScrollOffsetState = 0;
    return true;
  }

  setHistoryPageSize(lines: number): void {
    this.historyPageSize = Math.max(1, lines);
  }

  sendSelected(text: string): boolean {
    const node = this.selectedNode();
    if (!node || !text.trim()) return false;
    this.view.requestSend(node.key, text);
    return true;
  }

  scrollHistoryPage(direction: -1 | 1): void {
    this.historyScrollOffsetState = Math.max(
      0,
      this.historyScrollOffsetState + direction * this.historyPageSize,
    );
  }

  clampHistoryScroll(maxOffset: number): void {
    this.historyScrollOffsetState = Math.min(
      Math.max(0, this.historyScrollOffsetState),
      Math.max(0, maxOffset),
    );
  }
}

function oneLine(text: string): string {
  return sanitizeText(text).replace(/\s+/g, " ").trim();
}

/** Keep only the newest paragraph/markdown step from one reasoning block. */
export function latestThinkingStep(text: string): string {
  const clean = sanitizeText(text).trim();
  if (!clean) return "";
  const paragraphs = clean.split(/\n\s*\n+/).filter((part) => part.trim());
  let latest = paragraphs[paragraphs.length - 1]?.trim() ?? "";

  const lines = latest
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const markdownStep = (line: string) =>
    /^#{1,6}\s+\S/.test(line) || /^\*\*[^*].*\*\*$/.test(line);
  if (lines.length > 1 && lines.every(markdownStep)) {
    latest = lines[lines.length - 1] ?? latest;
  } else {
    const boldSteps = latest.match(/\*\*[^*]+\*\*/g);
    if (
      boldSteps &&
      boldSteps.length > 1 &&
      latest.replace(/\*\*[^*]+\*\*/g, "").trim() === ""
    ) {
      latest = boldSteps[boldSteps.length - 1] ?? latest;
    }
  }
  return oneLine(latest);
}

/** Latest visible reasoning step: live stream first, then finalized history. */
export function latestThinking(snapshot: SubagentSnapshot): string {
  const live = latestThinkingStep(snapshot.liveAssistant?.thinking ?? "");
  if (live) return live;

  for (let itemIndex = snapshot.transcript.length - 1; itemIndex >= 0; itemIndex--) {
    const item = snapshot.transcript[itemIndex];
    if (item?.kind !== "assistant") continue;
    for (let partIndex = item.parts.length - 1; partIndex >= 0; partIndex--) {
      const part = item.parts[partIndex];
      if (part?.type !== "thinking" || part.redacted) continue;
      const thinking = latestThinkingStep(part.text);
      if (thinking) return thinking;
    }
  }
  return "";
}

function snapshotContextParts(snapshot: SubagentSnapshot) {
  const tokens = snapshot.usage.tokens;
  const contextWindow =
    snapshot.usage.contextWindow ?? snapshot.meta.contextWindow;
  const current =
    typeof tokens === "number" && Number.isFinite(tokens) && tokens >= 0
      ? formatCompactTokens(tokens)
      : "?";
  const capacity =
    typeof contextWindow === "number" &&
    Number.isFinite(contextWindow) &&
    contextWindow > 0
      ? formatCompactTokens(contextWindow)
      : "?";
  return { current, capacity, percent: contextPercent({ tokens, contextWindow }) };
}

export function formatSnapshotContext(snapshot: SubagentSnapshot): string {
  const { current, capacity, percent } = snapshotContextParts(snapshot);
  return `ctx ${current}/${capacity}${percent === undefined ? "" : ` (${percent}%)`}`;
}

function formatSnapshotContextCompact(snapshot: SubagentSnapshot): string {
  const { current, capacity, percent } = snapshotContextParts(snapshot);
  return `${current}/${capacity}${percent === undefined ? "" : ` ${percent}%`}`;
}

function short(text: string, width: number): string {
  return truncateToWidth(oneLine(text), Math.max(1, width), "…");
}

function modelLabel(snapshot: SubagentSnapshot): string {
  return oneLine(snapshot.meta.modelLabel ?? "?") || "?";
}

function compactStatusGlyph(snapshot: SubagentSnapshot, theme: Theme): string {
  switch (snapshot.status) {
    case "running":
      return theme.fg("warning", "■");
    case "done":
      return theme.fg("success", "✓");
    case "error":
      return theme.fg("error", "✕");
  }
}

function compactStatusGlyphPlain(snapshot: SubagentSnapshot): string {
  return snapshot.status === "running"
    ? "■"
    : snapshot.status === "done"
      ? "✓"
      : "✕";
}

function renderRows(
  nodes: ReadonlyArray<SubagentTreeNode>,
  selected: SubagentTreeNode,
  focused: boolean,
  width: number,
  theme: Theme,
): string[] {
  const canCycle = nodes.length > 1;
  const titleWidth = Math.max(8, Math.min(14, Math.floor(width / 8)));
  const modelWidth = Math.max(10, Math.min(22, Math.floor(width / 4)));

  return nodes.map((node) => {
    const snapshot = node.snapshot;
    const isSelected = node.key === selected.key;
    const marker = focused
      ? isSelected
        ? theme.fg("accent", canCycle ? "↑↓ " : "↑  ")
        : "   "
      : isSelected
        ? theme.fg("dim", "↓  ")
        : "   ";
    const branch = theme.fg("dim", subagentTreePrefix(node));
    const prefix =
      `${marker}${branch}${compactStatusGlyph(snapshot, theme)} ` +
      theme.fg(
        focused && isSelected ? "accent" : "text",
        `${snapshot.id} ${short(snapshot.title, titleWidth)}`,
      ) +
      theme.fg(
        "muted",
        ` · ${snapshot.backend} · ${short(modelLabel(snapshot), modelWidth)} · ${formatSnapshotContextCompact(snapshot)} · `,
      ) +
      theme.fg("dim", "~ ");
    const thinking = latestThinking(snapshot) || "(no thinking yet)";
    if (focused && isSelected) {
      const plain =
        `${canCycle ? "↑↓ " : "↑  "}${subagentTreePrefix(node)}${compactStatusGlyphPlain(snapshot)} ` +
        `${snapshot.id} ${oneLine(short(snapshot.title, titleWidth))}` +
        ` · ${snapshot.backend} · ${oneLine(short(modelLabel(snapshot), modelWidth))}` +
        ` · ${formatSnapshotContextCompact(snapshot)} · ~ ${thinking}`;
      const clipped = sanitizeText(truncateToWidth(plain, width, ""));
      const padded =
        clipped + " ".repeat(Math.max(0, width - visibleWidth(clipped)));
      return theme.bg("selectedBg", theme.fg("text", theme.bold(padded)));
    }
    return truncateToWidth(prefix + theme.fg("muted", thinking), width);
  });
}

export function renderRunningSubagents(
  nodes: ReadonlyArray<SubagentTreeNode>,
  selectedKey: string | undefined,
  width: number,
  theme: Theme,
  focused = false,
): string[] {
  if (width <= 0 || nodes.length === 0) return [];
  const selected = nodes.find((node) => node.key === selectedKey) ?? nodes[0];
  if (!selected) return [];
  const root = truncateToWidth(
    `   ${theme.fg("accent", "◇ ")}${theme.fg("muted", theme.bold("teamlead"))}`,
    width,
  );
  return [root, ...renderRows(nodes, selected, focused, width, theme)];
}

export class RunningSubagentsPane implements Component {
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly controller: RunningSubagentController;
  private readonly unsubscribe: () => void;
  private renderTimer?: ReturnType<typeof setTimeout>;
  private disposed = false;

  constructor(
    tui: TUI,
    theme: Theme,
    controller: RunningSubagentController,
    view: SubagentTreeView,
  ) {
    this.tui = tui;
    this.theme = theme;
    this.controller = controller;
    this.unsubscribe = view.subscribe(() => this.scheduleRender());
  }

  private scheduleRender(): void {
    if (this.renderTimer || this.disposed) return;
    this.renderTimer = setTimeout(() => {
      this.renderTimer = undefined;
      if (!this.disposed) this.tui.requestRender();
    }, RENDER_THROTTLE_MS);
  }

  render(width: number): string[] {
    const nodes = this.controller.nodes();
    return renderRunningSubagents(
      nodes,
      this.controller.selection.key,
      width,
      this.theme,
      this.controller.focused,
    );
  }

  invalidate(): void {}

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unsubscribe();
    if (this.renderTimer) clearTimeout(this.renderTimer);
    this.renderTimer = undefined;
  }
}

const ZERO_USAGE: AssistantMessage["usage"] = {
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

function parseArgsPreview(preview: string | undefined): Record<string, unknown> {
  if (!preview) return {};
  try {
    const parsed: unknown = JSON.parse(preview);
    return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : { value: parsed };
  } catch {
    return { preview };
  }
}

function assistantMessage(
  snapshot: SubagentSnapshot,
  parts: ReadonlyArray<TranscriptPart>,
): AssistantMessage {
  const content: AssistantMessage["content"] = parts.map((part) => {
    if (part.type === "text") return { type: "text", text: part.text };
    if (part.type === "thinking") {
      return {
        type: "thinking",
        thinking: part.redacted ? "[redacted reasoning]" : part.text,
        redacted: part.redacted,
      };
    }
    return {
      type: "toolCall",
      id: part.toolId,
      name: part.name,
      arguments: parseArgsPreview(part.argsPreview),
    };
  });
  return {
    role: "assistant",
    content,
    api: "pi-messages",
    provider: snapshot.backend,
    model: snapshot.meta.modelLabel ?? "subagent",
    usage: ZERO_USAGE,
    stopReason: content.some((part) => part.type === "toolCall")
      ? "toolUse"
      : "stop",
    timestamp: snapshot.createdAt,
  };
}

function toolExecutionComponent(
  tui: TUI,
  snapshot: SubagentSnapshot,
  item: {
    readonly toolId: string;
    readonly name: string;
    readonly argsPreview?: string;
    readonly outputPreview?: string;
    readonly isError?: boolean;
  },
  partial = false,
): ToolExecutionComponent {
  const tool = new ToolExecutionComponent(
    item.name,
    item.toolId,
    parseArgsPreview(item.argsPreview),
    { showImages: false },
    undefined,
    tui,
    snapshot.cwd,
  );
  tool.markExecutionStarted();
  tool.setArgsComplete();
  tool.updateResult(
    {
      content: [{ type: "text", text: item.outputPreview ?? "" }],
      isError: item.isError ?? false,
    },
    partial,
  );
  return tool;
}

/** Build Pi's own message/tool components from the normalized child transcript. */
function buildPiHistoryComponent(
  snapshot: SubagentSnapshot,
  tui: TUI,
  theme: Theme,
): Container {
  const container = new Container();
  const toolArgs = new Map<string, string | undefined>();
  const addUser = (text: string) => {
    if (container.children.length > 0) container.addChild(new Spacer(1));
    container.addChild(
      new UserMessageComponent(text, getMarkdownTheme(), 1),
    );
  };
  const addAssistant = (
    parts: ReadonlyArray<TranscriptPart>,
    streaming = false,
  ) => {
    const message = assistantMessage(snapshot, parts);
    const component = new AssistantMessageComponent(
      undefined,
      false,
      getMarkdownTheme(),
      "Thinking...",
      1,
    );
    component.updateContent(message, streaming);
    container.addChild(component);
    for (const part of parts) {
      if (part.type === "toolCall") toolArgs.set(part.toolId, part.argsPreview);
    }
  };

  for (const item of snapshot.transcript) {
    if (item.kind === "user") {
      addUser(item.text);
    } else if (item.kind === "assistant") {
      addAssistant(item.parts);
    } else if (item.kind === "toolResult") {
      container.addChild(
        toolExecutionComponent(tui, snapshot, {
          ...item,
          argsPreview: toolArgs.get(item.toolId),
        }),
      );
    } else {
      if (container.children.length > 0) container.addChild(new Spacer(1));
      container.addChild(renderCommunicationCard(item.message, theme));
    }
  }

  const liveParts: TranscriptPart[] = [];
  if (snapshot.liveAssistant?.thinking.trim()) {
    liveParts.push({ type: "thinking", text: snapshot.liveAssistant.thinking });
  }
  if (snapshot.liveAssistant?.text.trim()) {
    liveParts.push({ type: "text", text: snapshot.liveAssistant.text });
  }
  if (liveParts.length > 0) addAssistant(liveParts, true);

  for (const tool of snapshot.liveTools) {
    container.addChild(
      toolExecutionComponent(tui, snapshot, tool, !tool.done),
    );
  }
  for (const queued of snapshot.queued) {
    addUser(`[queued ${queued.kind}] ${queued.text}`);
  }
  return container;
}

function historyPaneHeight(
  tui: TUI,
  controller: RunningSubagentController,
): number {
  const rows = tui.terminal.rows || 30;
  // Only reserve the components mounted after this pane: the editor, compact
  // child rows, and normal usage/footer. Components before it (including the
  // teamlead transcript) must be pushed fully outside the visible viewport.
  return Math.max(4, rows - controller.count() - 6);
}

export class RunningSubagentHistoryPane implements Component {
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly controller: RunningSubagentController;
  private readonly unsubscribe: () => void;
  private renderTimer?: ReturnType<typeof setTimeout>;
  private disposed = false;

  constructor(
    tui: TUI,
    theme: Theme,
    controller: RunningSubagentController,
    view: SubagentTreeView,
  ) {
    this.tui = tui;
    this.theme = theme;
    this.controller = controller;
    this.unsubscribe = view.subscribe(() => this.scheduleRender());
  }

  private scheduleRender(): void {
    if (this.renderTimer || this.disposed) return;
    this.renderTimer = setTimeout(() => {
      this.renderTimer = undefined;
      if (!this.disposed) this.tui.requestRender();
    }, RENDER_THROTTLE_MS);
  }

  render(width: number): string[] {
    if (!this.controller.focused) return [];
    const node = this.controller.selectedNode();
    const snapshot = node?.snapshot;
    if (!node || !snapshot || width <= 0) return [];

    const height = historyPaneHeight(this.tui, this.controller);
    const transcript = buildPiHistoryComponent(
      snapshot,
      this.tui,
      this.theme,
    ).render(width);
    const transcriptCapacity = Math.max(1, height - 3);
    this.controller.setHistoryPageSize(transcriptCapacity);
    this.controller.clampHistoryScroll(
      Math.max(0, transcript.length - transcriptCapacity),
    );
    const end = transcript.length - this.controller.historyScrollOffset;
    const visible = transcript.slice(
      Math.max(0, end - transcriptCapacity),
      Math.max(0, end),
    );

    const header = truncateToWidth(
      this.theme.fg(
        "accent",
        this.theme.bold(`${node.idPath.join(" › ")} · ${snapshot.title}`),
      ) +
        this.theme.fg(
          "muted",
          ` · ${snapshot.backend} · ${modelLabel(snapshot)} · ${formatSnapshotContext(snapshot)}`,
        ),
      width,
    );
    const border = this.theme.fg("borderAccent", "─".repeat(width));
    const body = visible.length > 0 ? [...visible] : [this.theme.fg("dim", "(no history yet)")];
    while (body.length < transcriptCapacity) body.unshift("");
    const footer = truncateToWidth(
      this.theme.fg(
        "dim",
        `${this.controller.historyScrollOffset > 0 ? `${this.controller.historyScrollOffset} lines below · ` : ""}↑/↓ agent · ↑ on first/esc back · pgup/pgdn history`,
      ),
      width,
    );

    return [header, border, ...body.slice(-transcriptCapacity), footer].map(
      (line) => {
        const clipped = truncateToWidth(line, width, "");
        const padded = clipped + " ".repeat(Math.max(0, width - visibleWidth(clipped)));
        return padded;
      },
    );
  }

  invalidate(): void {}

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unsubscribe();
    if (this.renderTimer) clearTimeout(this.renderTimer);
    this.renderTimer = undefined;
  }
}

export function hydrateEditorHistory(
  editor: EditorComponent,
  promptHistory: ReadonlyArray<string>,
): void {
  for (const prompt of promptHistory) editor.addToHistory?.(prompt);
}

/**
 * Decorate the editor instance returned by the previous factory. Keeping the
 * same object preserves focus/IME, autocomplete, app handlers, and any custom
 * behavior supplied by an earlier editor extension.
 */
const RUNNING_EDITOR_REFRESH = Symbol.for(
  "pi.subagents.running-editor.refresh.v1",
);

export function createRunningSubagentEditorFactory(
  previous: EditorFactory | undefined,
  controller: RunningSubagentController,
  promptHistory: ReadonlyArray<string> = [],
  focusedBorderColor?: (text: string) => string,
): EditorFactory {
  return (tui, theme, keybindings) => {
    const editor =
      previous?.(tui, theme, keybindings) ??
      new CustomEditor(tui, theme, keybindings);
    const existingRefresh = (
      editor as EditorComponent & {
        [RUNNING_EDITOR_REFRESH]?: (
          controller: RunningSubagentController,
          border?: (text: string) => string,
        ) => void;
      }
    )[RUNNING_EDITOR_REFRESH];
    if (existingRefresh) {
      existingRefresh(controller, focusedBorderColor);
      return editor;
    }

    // Pi transfers text but not the default editor's private history when a
    // custom editor is installed after session restore. Earlier custom-editor
    // factories own their own history policy; hydrate only our fallback.
    if (!previous) hydrateEditorHistory(editor, promptHistory);
    let activeController = controller;
    let activeFocusedBorderColor = focusedBorderColor;
    const handleInput = editor.handleInput.bind(editor);
    const render = editor.render.bind(editor);
    editor.render = (width: number) => {
      if (
        !activeController.focused ||
        !activeFocusedBorderColor ||
        !editor.borderColor
      ) {
        return render(width);
      }
      const normalBorderColor = editor.borderColor;
      editor.borderColor = activeFocusedBorderColor;
      try {
        return render(width);
      } finally {
        editor.borderColor = normalBorderColor;
      }
    };

    const unfocus = () => {
      activeController.unfocus();
      // Removing a terminal-sized history pane is a large shrink. Force a
      // complete redraw so Pi's teamlead transcript returns at the viewport
      // instead of being left above the terminal's current scroll position.
      tui.requestRender(true);
    };

    editor.handleInput = (data: string) => {
      const empty = editor.getText().length === 0;
      const count = activeController.count();

      if (activeController.focused) {
        if (count === 0) {
          unfocus();
          handleInput(data);
          return;
        }
        if (matchesKey(data, Key.escape)) {
          unfocus();
          return;
        }

        if (empty) {
          if (matchesKey(data, Key.up)) {
            if (activeController.selection.index === 0) {
              unfocus();
            } else {
              activeController.move(-1);
              tui.requestRender();
            }
            return;
          }
          if (matchesKey(data, Key.down)) {
            activeController.move(1);
            tui.requestRender();
            return;
          }
          if (matchesKey(data, Key.pageUp)) {
            activeController.scrollHistoryPage(1);
            tui.requestRender();
            return;
          }
          if (matchesKey(data, Key.pageDown)) {
            activeController.scrollHistoryPage(-1);
            tui.requestRender();
            return;
          }
          if (matchesKey(data, Key.right)) return;
        }

        if (keybindings.matches(data, "tui.input.submit")) {
          const text = editor.getText();
          if (activeController.sendSelected(text)) {
            editor.addToHistory?.(text);
            editor.setText("");
            tui.requestRender(true);
          }
          return;
        }

        // Keep the child history active while the user composes guidance.
        // Cursor movement, multiline editing, autocomplete, and shortcuts all
        // retain the normal Pi editor behavior.
        handleInput(data);
        return;
      }

      // Keep ordinary prompt-history navigation until the user explicitly
      // presses Down once to focus the running-subagent pane.
      if (empty && count > 0 && matchesKey(data, Key.down)) {
        activeController.focus();
        tui.requestRender(true);
        return;
      }
      handleInput(data);
    };

    (
      editor as EditorComponent & {
        [RUNNING_EDITOR_REFRESH]?: (
          controller: RunningSubagentController,
          border?: (text: string) => string,
        ) => void;
      }
    )[RUNNING_EDITOR_REFRESH] = (nextController, nextBorder) => {
      activeController.unfocus();
      activeController = nextController;
      activeFocusedBorderColor = nextBorder;
    };

    return editor;
  };
}
