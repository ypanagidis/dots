import assert from "node:assert/strict";
import test from "node:test";
import type { Theme } from "@earendil-works/pi-coding-agent";
import type { SubagentSnapshot } from "./src/domain.ts";
import type { SubagentTreeNode } from "./src/subagent-tree.ts";
import {
  reconcileDashboardSelection,
  renderDashboardTreeRow,
  type DashboardSelection,
} from "./src/ui/takeover.ts";

test("dashboard selection follows its qualified key and falls back by row", () => {
  const selection: DashboardSelection = { key: "child-7", index: 6 };

  reconcileDashboardSelection(selection, [
    { key: "child-new" },
    ...Array.from({ length: 8 }, (_, index) => ({
      key: `child-${index + 1}`,
    })),
  ]);
  assert.deepEqual(selection, { key: "child-7", index: 7 });

  reconcileDashboardSelection(selection, [
    ...Array.from({ length: 6 }, (_, index) => ({
      key: `child-${index + 1}`,
    })),
    { key: "child-8" },
    { key: "child-9" },
  ]);
  assert.deepEqual(selection, { key: "child-9", index: 7 });

  reconcileDashboardSelection(selection, [
    { key: "child-1" },
    { key: "child-2" },
  ]);
  assert.deepEqual(selection, { key: "child-2", index: 1 });

  reconcileDashboardSelection(selection, []);
  assert.deepEqual(selection, { key: undefined, index: 0 });
});

test("dashboard row renders nested tree connectors and stays within width", () => {
  const snapshot: SubagentSnapshot = {
    id: "sa-1",
    origin: "model",
    backend: "pi",
    title: "nested tests",
    prompt: "test",
    cwd: "/repo",
    allowedSubagentsDepth: 0,
    status: "running",
    run: 1,
    createdAt: Date.now(),
    meta: { backend: "pi", nativeSessionId: "nested-session" },
    usage: {},
    transcript: [],
    liveTools: [],
    queued: [],
    communications: [],
    pendingQuestions: [],
    finalText: "",
    turns: 0,
  };
  const node = {
    key: "nested-session",
    ownerKey: "parent-session",
    snapshot,
    depth: 1,
    ancestorLast: [false],
    isLast: true,
    idPath: ["sa-2", "sa-1"],
  } as unknown as SubagentTreeNode;
  const theme = {
    fg: (_color: string, text: string) => text,
  } as Theme;
  const row = renderDashboardTreeRow(node, true, 80, theme);
  assert.match(row, /│  └─/);
  assert.match(row, /nested tests/);
  assert.match(row, /sa-1/);
  assert.ok(row.length <= 80);
});
