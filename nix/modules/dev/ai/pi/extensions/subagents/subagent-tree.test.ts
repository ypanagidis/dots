import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { SubagentSnapshot } from "./src/domain.ts";
import type { SubagentReadModel } from "./src/manager.ts";
import {
  createSubagentTreeBridge,
  resolveSubagentTreeRegistry,
  SubagentTreeRegistry,
  subagentTreePrefix,
} from "./src/subagent-tree.ts";

function snapshot(
  id: string,
  nativeSessionId: string,
  overrides: Partial<SubagentSnapshot> = {},
): SubagentSnapshot {
  return {
    id,
    origin: "model",
    backend: "pi",
    title: `task ${id}`,
    prompt: "test",
    cwd: "/repo",
    allowedSubagentsDepth: 0,
    status: "running",
    run: 1,
    createdAt: 1,
    meta: { backend: "pi", nativeSessionId },
    usage: {},
    transcript: [],
    liveTools: [],
    queued: [],
    communications: [],
    pendingQuestions: [],
    finalText: "",
    turns: 0,
    ...overrides,
  };
}

function fakeView(initial: SubagentSnapshot[]) {
  let snapshots = initial;
  const listeners = new Set<() => void>();
  const sends: Array<{ id: string; text: string }> = [];
  const aborts: string[] = [];
  const view: SubagentReadModel = {
    list: () => snapshots,
    get: (id) => snapshots.find((entry) => entry.id === id),
    size: () => snapshots.length,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    subscribeTo: (_id, listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    requestSend: (id, text) => sends.push({ id, text }),
    requestAbort: (id) => aborts.push(id),
    setOnSettled: () => {},
    setOnMessage: () => {},
    setOnLifecycle: () => {},
  };
  return {
    view,
    sends,
    aborts,
    set(next: SubagentSnapshot[]) {
      snapshots = next;
      for (const listener of listeners) listener();
    },
  };
}

test("registry projects a recursive DFS tree with stable native-session keys", () => {
  const registry = new SubagentTreeRegistry();
  const root = fakeView([
    snapshot("sa-1", "session-a"),
    snapshot("sa-2", "session-b"),
  ]);
  const child = fakeView([
    snapshot("sa-1", "session-a1"),
    snapshot("sa-2", "session-a2"),
  ]);
  const grandchild = fakeView([snapshot("sa-1", "session-a1x")]);
  registry.register("root", root.view);
  registry.register("session-a", child.view);
  registry.register("session-a1", grandchild.view);

  const nodes = registry.view("root").list();
  assert.deepEqual(
    nodes.map((node) => ({
      key: node.key,
      depth: node.depth,
      path: node.idPath.join("/"),
      prefix: subagentTreePrefix(node),
    })),
    [
      { key: "session-a", depth: 0, path: "sa-1", prefix: "├─ " },
      { key: "session-a1", depth: 1, path: "sa-1/sa-1", prefix: "│  ├─ " },
      { key: "session-a1x", depth: 2, path: "sa-1/sa-1/sa-1", prefix: "│  │  └─ " },
      { key: "session-a2", depth: 1, path: "sa-1/sa-2", prefix: "│  └─ " },
      { key: "session-b", depth: 0, path: "sa-2", prefix: "└─ " },
    ],
  );
});

test("running projection retains an ancestor branch and hides settled leaves", () => {
  const registry = new SubagentTreeRegistry();
  const root = fakeView([
    snapshot("sa-1", "session-a", { status: "done" }),
    snapshot("sa-2", "session-b", { status: "done" }),
  ]);
  const child = fakeView([snapshot("sa-1", "session-a1")]);
  registry.register("root", root.view);
  registry.register("session-a", child.view);

  assert.deepEqual(
    registry
      .view("root")
      .list({ runningOnly: true, modelOnly: true })
      .map((node) => node.key),
    ["session-a", "session-a1"],
  );
});

test("qualified tree actions route duplicate local ids to their owning manager", () => {
  const registry = new SubagentTreeRegistry();
  const root = fakeView([snapshot("sa-1", "session-a")]);
  const child = fakeView([snapshot("sa-1", "session-a1")]);
  registry.register("root", root.view);
  registry.register("session-a", child.view);
  const tree = registry.view("root");

  tree.requestSend("session-a1", "nested guidance");
  tree.requestAbort("session-a1");
  assert.deepEqual(root.sends, []);
  assert.deepEqual(child.sends, [{ id: "sa-1", text: "nested guidance" }]);
  assert.deepEqual(child.aborts, ["sa-1"]);
});

test("registry reacts to descendant changes and unregister removes the subtree", () => {
  const registry = new SubagentTreeRegistry();
  const root = fakeView([snapshot("sa-1", "session-a")]);
  const child = fakeView([snapshot("sa-1", "session-a1")]);
  registry.register("root", root.view);
  const childRegistration = registry.register("session-a", child.view);
  const tree = registry.view("root");
  let changes = 0;
  const unsubscribe = tree.subscribe(() => changes++);

  child.set([
    snapshot("sa-1", "session-a1"),
    snapshot("sa-2", "session-a2"),
  ]);
  assert.equal(changes, 1);
  assert.deepEqual(tree.list().map((node) => node.key), [
    "session-a",
    "session-a1",
    "session-a2",
  ]);

  childRegistration.unregister();
  assert.equal(changes, 2);
  assert.deepEqual(tree.list().map((node) => node.key), ["session-a"]);
  unsubscribe();
});

test("bridge hands the root-owned registry to a separately loaded extension", () => {
  const listeners = new Map<string, Set<(value: unknown) => void>>();
  const events = {
    on(name: string, listener: (value: unknown) => void) {
      const set = listeners.get(name) ?? new Set();
      set.add(listener);
      listeners.set(name, set);
    },
    emit(name: string, value: unknown) {
      for (const listener of listeners.get(name) ?? []) listener(value);
    },
  };
  const pi = { events } as unknown as ExtensionAPI;
  const root = new SubagentTreeRegistry();
  createSubagentTreeBridge(root).factory(pi);
  assert.equal(resolveSubagentTreeRegistry(pi), root);
});
