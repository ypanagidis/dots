import assert from "node:assert/strict";
import test from "node:test";
import { createEventBus, initTheme } from "@earendil-works/pi-coding-agent";
import subagentsExtension from "./index.ts";
import {
  createSubagentTreeBridge,
  SubagentTreeRegistry,
} from "./src/subagent-tree.ts";
import type {
  ExtensionAPI,
  ExtensionContext,
  ExtensionUIContext,
  KeybindingsManager,
  SessionEntry,
  Theme,
} from "@earendil-works/pi-coding-agent";
import type { EditorComponent, EditorTheme, TUI } from "@earendil-works/pi-tui";
import { visibleWidth } from "@earendil-works/pi-tui";
import type { SubagentSnapshot } from "./src/domain.ts";
import type { SubagentReadModel } from "./src/manager.ts";
import type {
  SubagentTreeNode,
  SubagentTreeOptions,
  SubagentTreeView,
} from "./src/subagent-tree.ts";
import {
  createRunningSubagentEditorFactory,
  formatSnapshotContext,
  latestThinking,
  reconcileRunningSelection,
  renderRunningSubagents,
  RunningSubagentController,
  RunningSubagentHistoryPane,
  RunningSubagentsPane,
  runningModelSubagents,
  sessionPromptHistory,
  type RunningSelection,
} from "./src/ui/running-subagents.ts";

type EditorFactory = NonNullable<
  ReturnType<ExtensionUIContext["getEditorComponent"]>
>;

function snapshot(
  id: string,
  overrides: Partial<SubagentSnapshot> = {},
): SubagentSnapshot {
  return {
    id,
    origin: "model",
    backend: "pi",
    title: `task ${id}`,
    prompt: "test",
    cwd: "/repo",
    status: "running",
    run: 1,
    createdAt: 1,
    meta: {
      backend: "pi",
      modelLabel: "openai-codex/gpt-5.6-sol",
      contextWindow: 272_000,
    },
    usage: { tokens: 61_000, contextWindow: 272_000 },
    transcript: [],
    liveTools: [],
    queued: [],
    communications: [],
    pendingQuestions: [],
    finalText: "",
    turns: 0,
    ...overrides,
    allowedSubagentsDepth: overrides.allowedSubagentsDepth ?? 0,
  };
}

const theme = {
  fg: (_color: string, text: string) => text,
  bg: (_color: string, text: string) => text,
  bold: (text: string) => text,
  italic: (text: string) => text,
} as unknown as Theme;

const ansiTheme = {
  fg: (_color: string, text: string) => `\x1b[31m${text}\x1b[39m`,
  bg: (_color: string, text: string) => `\x1b[44m${text}\x1b[49m`,
  bold: (text: string) => `\x1b[1m${text}\x1b[22m`,
  italic: (text: string) => `\x1b[3m${text}\x1b[23m`,
} as unknown as Theme;

function fakeView(initial: SubagentSnapshot[]) {
  let snapshots = initial;
  const listeners = new Set<() => void>();
  const sends: Array<{ id: string; text: string }> = [];
  let unsubscribeCount = 0;
  const view: SubagentReadModel = {
    list: () => snapshots,
    get: (id) => snapshots.find((entry) => entry.id === id),
    size: () => snapshots.length,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => {
        if (listeners.delete(listener)) unsubscribeCount++;
      };
    },
    subscribeTo: (_id, listener) => {
      listeners.add(listener);
      return () => {
        if (listeners.delete(listener)) unsubscribeCount++;
      };
    },
    requestSend: (id, text) => sends.push({ id, text }),
    requestAbort: () => {},
    setOnSettled: () => {},
    setOnMessage: () => {},
    setOnLifecycle: () => {},
  };
  const treeNodes = (
    options: SubagentTreeOptions = {},
  ): ReadonlyArray<SubagentTreeNode> => {
    const visible = snapshots.filter(
      (entry) =>
        (!options.modelOnly || entry.origin === "model") &&
        (!options.runningOnly || entry.status === "running"),
    );
    return visible.map((entry, index) => ({
      key: `root\0${entry.id}`,
      ownerKey: "root",
      snapshot: entry,
      ownerView: view,
      depth: 0,
      ancestorLast: [],
      isLast: index === visible.length - 1,
      idPath: [entry.id],
    }));
  };
  const tree: SubagentTreeView = {
    list: treeNodes,
    get: (key) => treeNodes().find((node) => node.key === key),
    size: () => snapshots.length,
    directKey: (id) => treeNodes().find((node) => node.snapshot.id === id)?.key,
    subscribe: view.subscribe,
    subscribeTo: (_key, listener) => view.subscribe(listener),
    requestSend: (key, text) => {
      const node = treeNodes().find((entry) => entry.key === key);
      if (node) view.requestSend(node.snapshot.id, text);
    },
    requestAbort: (key) => {
      const node = treeNodes().find((entry) => entry.key === key);
      if (node) view.requestAbort(node.snapshot.id);
    },
  };
  return {
    view: tree,
    managerView: view,
    tree,
    nodes: treeNodes,
    set(next: SubagentSnapshot[]) {
      snapshots = next;
      for (const listener of listeners) listener();
    },
    notify() {
      for (const listener of listeners) listener();
    },
    sends,
    unsubscribeCount: () => unsubscribeCount,
  };
}

test("session prompt history mirrors restored user text", () => {
  const base = { id: "1", parentId: null, timestamp: "now" };
  const entries = [
    {
      ...base,
      type: "message",
      message: { role: "user", content: "first", timestamp: 1 },
    },
    {
      ...base,
      id: "2",
      type: "message",
      message: {
        role: "user",
        content: [
          { type: "text", text: "second" },
          {
            type: "image",
            source: { type: "base64", mediaType: "image/png", data: "" },
          },
          { type: "text", text: " prompt" },
        ],
        timestamp: 2,
      },
    },
    {
      ...base,
      id: "3",
      type: "message",
      message: { role: "assistant", content: [], timestamp: 3 },
    },
  ] as unknown as SessionEntry[];
  assert.deepEqual(sessionPromptHistory(entries), ["first", "second prompt"]);
});

test("running pane includes only running model-origin snapshots", () => {
  const visible = snapshot("sa-1");
  assert.deepEqual(
    runningModelSubagents([
      visible,
      snapshot("sa-2", { status: "done" }),
      snapshot("btw-1", { origin: "btw" }),
    ]),
    [visible],
  );
});

test("running selection follows qualified keys, falls back by row, and wraps", () => {
  const selection: RunningSelection = { key: "child-2", index: 1 };
  reconcileRunningSelection(selection, [
    { key: "child-new" },
    { key: "child-1" },
    { key: "child-2" },
  ]);
  assert.deepEqual(selection, { key: "child-2", index: 2 });

  reconcileRunningSelection(selection, [
    { key: "child-new" },
    { key: "child-1" },
  ]);
  assert.deepEqual(selection, { key: "child-1", index: 1 });

  const source = fakeView([snapshot("sa-1"), snapshot("sa-2")]);
  const controller = new RunningSubagentController(source.view);
  assert.equal(controller.selected()?.id, "sa-1");
  assert.equal(controller.move(-1), true);
  assert.equal(controller.selected()?.id, "sa-2");
  assert.equal(controller.move(1), true);
  assert.equal(controller.selected()?.id, "sa-1");

  const focusStates: boolean[] = [];
  controller.setOnFocusChange((focused) => focusStates.push(focused));
  assert.equal(controller.focus(), true);
  assert.equal(controller.unfocus(), true);
  assert.deepEqual(focusStates, [true, false]);
});

test("latest thinking prefers live reasoning and falls back to finalized history", () => {
  const finalized = snapshot("sa-1", {
    transcript: [
      {
        kind: "assistant",
        parts: [
          { type: "thinking", text: "old\n reasoning" },
          { type: "thinking", text: "hidden", redacted: true },
          { type: "text", text: "answer" },
        ],
      },
    ],
  });
  assert.equal(latestThinking(finalized), "old reasoning");
  assert.equal(
    latestThinking({
      ...finalized,
      liveAssistant: { text: "", thinking: "live\tstep" },
    }),
    "live step",
  );
  assert.equal(
    latestThinking({
      ...finalized,
      liveAssistant: {
        text: "",
        thinking:
          "**Refactoring getNodeSubtitle calls**\n\n**Standardizing voice labels**",
      },
    }),
    "**Standardizing voice labels**",
  );
  assert.equal(
    latestThinking({
      ...finalized,
      liveAssistant: {
        text: "",
        thinking: "**First step** **Newest step**",
      },
    }),
    "**Newest step**",
  );
  assert.equal(latestThinking(snapshot("sa-2")), "");
});

test("context formatting distinguishes unknown occupancy from zero", () => {
  assert.equal(
    formatSnapshotContext(snapshot("sa-1", { usage: {} })),
    "ctx ?/272k",
  );
  assert.equal(
    formatSnapshotContext(
      snapshot("sa-1", {
        usage: {},
        meta: { backend: "pi", modelLabel: "model" },
      }),
    ),
    "ctx ?/?",
  );
});

test("running rows expose metadata and stay within width", () => {
  const snapshots = [
    snapshot("sa-1", {
      title: "API audit",
      liveAssistant: { text: "", thinking: "Inspecting editor lifecycle" },
    }),
    snapshot("sa-2", {
      title: "tests",
      liveAssistant: { text: "", thinking: "Adding cancellation coverage" },
    }),
  ];

  const source = fakeView(snapshots);
  const nodes = source.nodes();
  const selectedKey = source.view.directKey("sa-2");
  const rows = renderRunningSubagents(nodes, selectedKey, 200, theme);
  assert.equal(rows.length, 3);
  assert.match(rows[0] ?? "", /teamlead/);
  assert.match(rows[1] ?? "", /Inspecting editor lifecycle/);
  assert.match(rows[2] ?? "", /Adding cancellation coverage/);
  assert.match(rows[2] ?? "", /61k\/272k 22%/);
  assert.match(rows[2] ?? "", /↓/);

  const focused = renderRunningSubagents(
    nodes,
    selectedKey,
    200,
    ansiTheme,
    true,
  );
  assert.match(focused[2] ?? "", /↑↓/);
  assert.match(focused[2] ?? "", /\x1b\[44m/);
  assert.match(focused[2] ?? "", /\x1b\[1m/);
  assert.doesNotMatch(focused[2] ?? "", /\x1b\[0m/);
  assert.equal((focused[2]?.match(/\x1b\[44m/g) ?? []).length, 1);
  assert.equal((focused[2]?.match(/\x1b\[49m/g) ?? []).length, 1);
  assert.doesNotMatch(
    renderRunningSubagents(nodes, selectedKey, 200, ansiTheme)[2] ?? "",
    /\x1b\[44m/,
  );

  for (const renderTheme of [theme, ansiTheme]) {
    for (const line of renderRunningSubagents(
      nodes,
      source.view.directKey("sa-1"),
      32,
      renderTheme,
    )) {
      assert.ok(visibleWidth(line) <= 32, `${visibleWidth(line)}`);
    }
  }
});

test("running tree distinguishes settled ancestors from active descendants", () => {
  const ancestor = snapshot("sa-1", { status: "done", title: "parent" });
  const descendant = snapshot("sa-1", { title: "child" });
  const source = fakeView([ancestor]);
  const nodes: SubagentTreeNode[] = [
    {
      key: "parent-session",
      ownerKey: "root",
      snapshot: ancestor,
      ownerView: source.managerView,
      depth: 0,
      ancestorLast: [],
      isLast: true,
      idPath: ["sa-1"],
    },
    {
      key: "child-session",
      ownerKey: "parent-session",
      snapshot: descendant,
      ownerView: source.managerView,
      depth: 1,
      parentKey: "parent-session",
      ancestorLast: [true],
      isLast: true,
      idPath: ["sa-1", "sa-1"],
    },
  ];
  const rows = renderRunningSubagents(nodes, "child-session", 120, theme);
  assert.match(rows[1] ?? "", /✓.*parent/);
  assert.match(rows[2] ?? "", /■.*child/);
});

test("history pane uses Pi components and preserves the bottom dock", () => {
  initTheme("dark", false);
  const source = fakeView([
    snapshot("sa-1", {
      transcript: [
        {
          kind: "assistant",
          parts: [
            { type: "thinking", text: "Investigating" },
            { type: "text", text: "Full historical answer" },
            {
              type: "toolCall",
              toolId: "tool-1",
              name: "bash",
              argsPreview: '{"command":"pwd"}',
            },
          ],
        },
        {
          kind: "toolResult",
          toolId: "tool-1",
          name: "bash",
          isError: false,
          outputPreview: "/repo",
        },
        {
          kind: "communication",
          message: {
            messageId: "lead-msg-1",
            kind: "guidance",
            text: "Focus on the parser boundary.",
            createdAt: 2,
          },
        },
      ],
    }),
  ]);
  const controller = new RunningSubagentController(source.view);
  const pane = new RunningSubagentHistoryPane(
    {
      terminal: { rows: 30 },
      requestRender: () => {},
    } as unknown as TUI,
    theme,
    controller,
    source.view,
  );
  assert.deepEqual(pane.render(80), []);
  controller.focus();
  const rendered = pane.render(80);
  assert.ok(rendered.some((line) => line.includes("Full historical answer")));
  assert.ok(rendered.some((line) => line.includes("/repo")));
  assert.ok(rendered.some((line) => line.includes("guidance from teamlead")));
  assert.ok(
    rendered.some((line) => line.includes("Focus on the parser boundary")),
  );
  // 30 terminal rows minus one compact row, tree root, and five dock rows.
  assert.equal(rendered.length, 23);
  pane.dispose();
});

test("fallback editor receives restored prompt history", () => {
  const source = fakeView([snapshot("sa-1")]);
  const controller = new RunningSubagentController(source.view);
  const factory = createRunningSubagentEditorFactory(undefined, controller, [
    "restored one",
    "restored two",
  ]);
  const editor = factory(
    { requestRender: () => {} } as unknown as TUI,
    {
      borderColor: (text: string) => text,
      selectList: {},
    } as EditorTheme,
    { matches: () => false } as unknown as KeybindingsManager,
  );

  editor.handleInput("\x1b[A");
  assert.equal(editor.getText(), "restored two");
});

function editorFixture(focusedBorderColor?: (text: string) => string) {
  const source = fakeView([snapshot("sa-1"), snapshot("sa-2")]);
  const controller = new RunningSubagentController(source.view);
  const delegated: string[] = [];
  const editorHistory: string[] = [];
  let text = "";
  const editor: EditorComponent = {
    render: () => [editor.borderColor?.("─") ?? "─"],
    invalidate: () => {},
    getText: () => text,
    setText: (value) => {
      text = value;
    },
    handleInput: (data) => delegated.push(data),
    addToHistory: (value) => editorHistory.push(value),
    borderColor: (value) => `normal:${value}`,
  };
  const previous: EditorFactory = () => editor;
  let renderRequests = 0;
  const forcedRenders: boolean[] = [];
  const wrapped = createRunningSubagentEditorFactory(
    previous,
    controller,
    [],
    focusedBorderColor,
  )(
    {
      requestRender: (force?: boolean) => {
        renderRequests++;
        forcedRenders.push(force === true);
      },
    } as unknown as TUI,
    {} as EditorTheme,
    {
      matches: (data: string, action: string) =>
        action === "tui.input.submit" && data === "\r",
    } as KeybindingsManager,
  );
  return {
    source,
    controller,
    delegated,
    editorHistory,
    wrapped,
    renderRequests: () => renderRequests,
    forcedRenders,
  };
}

test("re-wrapping a proxied editor refreshes instead of recursing", () => {
  const firstSource = fakeView([snapshot("sa-1")]);
  const secondSource = fakeView([snapshot("sa-2")]);
  const firstController = new RunningSubagentController(firstSource.view);
  const secondController = new RunningSubagentController(secondSource.view);
  const delegated: string[] = [];
  let text = "";
  const base: EditorComponent = {
    render: () => ["─"],
    invalidate: () => {},
    getText: () => text,
    setText: (value) => {
      text = value;
    },
    handleInput: (data) => delegated.push(data),
  };
  const first = createRunningSubagentEditorFactory(() => base, firstController)(
    { requestRender: () => {} } as unknown as TUI,
    {} as EditorTheme,
    { matches: () => false } as unknown as KeybindingsManager,
  );
  const proxy = new Proxy(first, {
    get(target, property) {
      if (property === "handleInput") {
        return (data: string) => target.handleInput(data);
      }
      return Reflect.get(target, property);
    },
    set: (target, property, value) => Reflect.set(target, property, value),
  });
  const refreshed = createRunningSubagentEditorFactory(
    () => proxy,
    secondController,
  )(
    { requestRender: () => {} } as unknown as TUI,
    {} as EditorTheme,
    { matches: () => false } as unknown as KeybindingsManager,
  );

  refreshed.handleInput("\x1b[B");
  assert.equal(firstController.focused, false);
  assert.equal(secondController.focused, true);
  refreshed.handleInput("x");
  assert.deepEqual(delegated, ["x"]);
});

test("Up exits from the first row while Up/Down navigate other rows", () => {
  const { controller, delegated, forcedRenders, wrapped } = editorFixture();

  wrapped.handleInput("\x1b[A");
  assert.deepEqual(delegated, ["\x1b[A"]);
  wrapped.handleInput("\x1b[B");
  assert.equal(controller.focused, true);
  assert.equal(controller.selected()?.id, "sa-1");

  // Left is no longer an exit key; extensions such as background tasks may
  // own it without trapping the user in this view.
  wrapped.handleInput("\x1b[D");
  assert.equal(controller.focused, true);
  assert.deepEqual(delegated, ["\x1b[A", "\x1b[D"]);

  wrapped.handleInput("\x1b[B");
  assert.equal(controller.selected()?.id, "sa-2");
  wrapped.handleInput("\x1b[A");
  assert.equal(controller.selected()?.id, "sa-1");

  wrapped.handleInput("\x1b[5~");
  assert.equal(controller.historyScrollOffset, 6);
  wrapped.handleInput("\x1b[6~");
  assert.equal(controller.historyScrollOffset, 0);

  wrapped.handleInput("\x1b[A");
  assert.equal(controller.focused, false);
  assert.equal(forcedRenders[0], true);
  assert.equal(forcedRenders[forcedRenders.length - 1], true);

  wrapped.handleInput("\x1b[1;3B");
  assert.deepEqual(delegated, ["\x1b[A", "\x1b[D", "\x1b[1;3B"]);
  wrapped.setText(" ");
  wrapped.handleInput("\x1b[B");
  assert.deepEqual(delegated, ["\x1b[A", "\x1b[D", "\x1b[1;3B", "\x1b[B"]);
});

test("typing while focused keeps the subagent view and normal editor behavior", () => {
  const { controller, delegated, wrapped } = editorFixture();
  wrapped.handleInput("\x1b[B");
  assert.equal(controller.focused, true);
  wrapped.handleInput("x");
  assert.equal(controller.focused, true);
  assert.deepEqual(delegated, ["x"]);
});

test("submitting while focused prompts the selected subagent", () => {
  const { controller, editorHistory, source, wrapped } = editorFixture();
  wrapped.handleInput("\x1b[B");
  wrapped.setText("Please inspect the failing test");
  wrapped.handleInput("\r");

  assert.equal(controller.focused, true);
  assert.equal(wrapped.getText(), "");
  assert.deepEqual(source.sends, [
    { id: "sa-1", text: "Please inspect the failing test" },
  ]);
  assert.deepEqual(editorHistory, ["Please inspect the failing test"]);

  wrapped.handleInput("\x1b[B");
  wrapped.setText("Now check the docs");
  wrapped.handleInput("\r");
  assert.deepEqual(source.sends[1], {
    id: "sa-2",
    text: "Now check the docs",
  });
});

test("focused pane colors only the prompt border", () => {
  const { controller, wrapped } = editorFixture((value) => `accent:${value}`);
  assert.deepEqual(wrapped.render(80), ["normal:─"]);
  wrapped.handleInput("\x1b[B");
  assert.equal(controller.focused, true);
  assert.deepEqual(wrapped.render(80), ["accent:─"]);
  wrapped.handleInput("\x1b[A");
  assert.equal(controller.focused, false);
  assert.deepEqual(wrapped.render(80), ["normal:─"]);
});

for (const reason of ["startup", "reload", "resume"] as const) {
  for (const replacementOrder of ["before", "after"] as const) {
    test(`Down focuses cards when another editor loads ${replacementOrder} subagents on ${reason}`, async (t) => {
      const source = fakeView([snapshot("sa-1")]);
      const registry = new SubagentTreeRegistry();
      type Hook = (event: { reason: string }, ctx: ExtensionContext) => unknown;
      const hooks = new Map<string, Hook>();
      // SAFETY: This host implements registration and the startup/shutdown
      // APIs exercised below. No model requests or tool execution take place.
      const pi = {
        events: createEventBus(),
        on: (event: string, handler: Hook) => hooks.set(event, handler),
        registerTool: () => {},
        registerCommand: () => {},
        registerMessageRenderer: () => {},
        registerEntryRenderer: () => {},
        getAllTools: () => [{ name: "subagent_spawn" }],
      } as unknown as ExtensionAPI;
      createSubagentTreeBridge(registry).factory(pi);
      subagentsExtension(pi);
      let factory: EditorFactory | undefined;
      let editor: EditorComponent | undefined;
      let workingVisible = true;
      let imagePasteCount = 0;
      let text = "";
      // Models the replacing factory used by pi-atomic-images. Unlike a
      // wrapping extension, it discards whichever editor was installed first.
      const replacement: EditorComponent = {
        render: () => [text],
        invalidate: () => {},
        getText: () => text,
        setText: (value) => {
          text = value;
        },
        handleInput: () => {
          imagePasteCount++;
        },
      };
      // SAFETY: These are the only TUI and keybinding methods used by the
      // editor decorator; widget factories are not mounted in this host.
      const tui = { requestRender: () => {} } as unknown as TUI;
      const editorTheme = {
        borderColor: (value: string) => value,
      } as EditorTheme;
      const keybindings = {
        matches: () => false,
      } as unknown as KeybindingsManager;
      const setEditorComponent = (next: EditorFactory | undefined) => {
        factory = next;
        editor = next?.(tui, editorTheme, keybindings);
      };
      // SAFETY: Empty real-session history avoids recovery I/O. The context
      // implements the complete startup, editor installation and teardown path.
      const ctx = {
        mode: "tui",
        hasUI: true,
        sessionManager: {
          getSessionId: () => "editor-composition",
          getBranch: () => [],
          getEntries: () => [],
          buildContextEntries: () => [],
        },
        ui: {
          theme,
          getEditorComponent: () => factory,
          setEditorComponent,
          setWidget: () => {},
          setStatus: () => {},
          setWorkingVisible: (visible: boolean) => {
            workingVisible = visible;
          },
        },
      } as unknown as ExtensionContext;
      t.after(async () => {
        await hooks.get("session_shutdown")?.({ reason: "quit" }, ctx);
      });
      if (replacementOrder === "before") setEditorComponent(() => replacement);
      await hooks.get("session_start")?.({ reason }, ctx);
      if (replacementOrder === "after") setEditorComponent(() => replacement);
      const registration = registry.register(
        "editor-composition",
        source.managerView,
      );
      t.after(registration.unregister);
      await hooks.get("resources_discover")?.({ reason: "startup" }, ctx);
      assert.ok(editor);
      assert.equal(editor, replacement, "preserve the image editor instance");
      editor.handleInput("\x1b[B");
      assert.equal(workingVisible, false, "Down must focus the child view");
      assert.equal(
        imagePasteCount,
        0,
        "navigation must not reach the image editor",
      );
      editor.handleInput("paste");
      assert.equal(
        imagePasteCount,
        1,
        "other input must reach the image editor",
      );
      const installed = factory;
      await hooks.get("resources_discover")?.({ reason: "reload" }, ctx);
      assert.equal(
        factory,
        installed,
        "discovery must not wrap the editor twice",
      );
      editor.handleInput("\x1b[A");
      assert.equal(workingVisible, true, "Up must return to the teamlead");
    });
  }
}

test("widget throttles reactive renders and unsubscribes on dispose", async () => {
  const source = fakeView([snapshot("sa-1")]);
  const controller = new RunningSubagentController(source.view);
  let renders = 0;
  const pane = new RunningSubagentsPane(
    {
      requestRender: () => {
        renders++;
      },
    } as unknown as TUI,
    theme,
    controller,
    source.view,
  );

  source.notify();
  source.notify();
  await new Promise((resolve) => setTimeout(resolve, 70));
  assert.equal(renders, 1);
  pane.dispose();
  assert.equal(source.unsubscribeCount(), 1);
  source.notify();
  await new Promise((resolve) => setTimeout(resolve, 70));
  assert.equal(renders, 1);
});
