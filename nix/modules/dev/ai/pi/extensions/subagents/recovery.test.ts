import assert from "node:assert/strict";
import test from "node:test";
import type { SessionEntry } from "@earendil-works/pi-coding-agent";
import type { SubagentSnapshot } from "./src/domain.ts";
import {
  buildSubagentRecoveryPrompt,
  checkpointFromSnapshot,
  isRecoverableCheckpoint,
  parseRecoveryCheckpoint,
  pendingRecoveryCompletionIdsFromEntries,
  recoveryCheckpointsFromEntries,
  recoveryPublicIdsFromEntries,
  SUBAGENT_RECOVERY_BOUNDARY_ENTRY_TYPE,
  SUBAGENT_RECOVERY_ENTRY_TYPE,
  SUBAGENT_RECOVERY_VERSION,
} from "./src/recovery.ts";

function snapshot(overrides: Partial<SubagentSnapshot> = {}): SubagentSnapshot {
  return {
    id: "sa-4",
    origin: "model",
    backend: "pi",
    title: "recover me",
    prompt: "finish the task",
    cwd: "/repo",
    allowedSubagentsDepth: 2,
    status: "running",
    run: 2,
    createdAt: 123,
    meta: { backend: "pi", sessionFilePath: "/sessions/child.jsonl" },
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

function customEntry(id: string, data: unknown): SessionEntry {
  return {
    type: "custom",
    customType: SUBAGENT_RECOVERY_ENTRY_TYPE,
    data,
    id,
    parentId: null,
    timestamp: "2026-01-01T00:00:00.000Z",
  };
}

function deliveredResult(id: string, completionId: string): SessionEntry {
  return {
    type: "custom_message",
    customType: "subagent-result",
    content: "finished",
    display: true,
    details: { completionId },
    id,
    parentId: null,
    timestamp: "2026-01-01T00:00:00.000Z",
  };
}

test("checkpointFromSnapshot preserves the stable child link", () => {
  const checkpoint = checkpointFromSnapshot(snapshot(), "suspended");
  assert.deepEqual(checkpoint, {
    version: SUBAGENT_RECOVERY_VERSION,
    id: "sa-4",
    origin: "model",
    title: "recover me",
    prompt: "finish the task",
    cwd: "/repo",
    allowedSubagentsDepth: 2,
    sessionFilePath: "/sessions/child.jsonl",
    run: 2,
    createdAt: 123,
    status: "suspended",
    settledAt: undefined,
    errorText: undefined,
    queued: undefined,
    pendingQuestions: undefined,
  });
  assert.equal(isRecoverableCheckpoint(checkpoint!), true);
});

test("recovery checkpoints fold latest state per run on the supplied branch", () => {
  const running = checkpointFromSnapshot(snapshot())!;
  const done = {
    ...running,
    status: "done" as const,
    settledAt: 456,
    resultText: "finished",
    delivery: "pending" as const,
  };
  const other = checkpointFromSnapshot(
    snapshot({
      id: "sa-8",
      meta: { backend: "pi", sessionFilePath: "/sessions/8.jsonl" },
    }),
    "suspended",
  )!;
  const entries = [
    customEntry("1", running),
    {
      ...customEntry("ignored", {}),
      customType: "some-other-extension",
    },
    customEntry("2", other),
    customEntry("3", done),
  ] as SessionEntry[];

  const folded = recoveryCheckpointsFromEntries(entries);
  assert.equal(folded.size, 2);
  assert.deepEqual(folded.get("sa-4:run-2"), done);
  assert.deepEqual(folded.get("sa-8:run-2"), other);
  assert.equal(isRecoverableCheckpoint(folded.get("sa-4:run-2")!), false);
});

test("successive runs retain pending completions and fork boundaries drop ownership", () => {
  const run2 = checkpointFromSnapshot(snapshot())!;
  const run2Done = {
    ...run2,
    status: "done" as const,
    delivery: "pending" as const,
  };
  const run3 = checkpointFromSnapshot(snapshot({ run: 3 }))!;
  const entries = [
    customEntry("1", run2),
    customEntry("2", run2Done),
    customEntry("3", run3),
  ];

  const folded = recoveryCheckpointsFromEntries(entries);
  assert.deepEqual([...folded.keys()], ["sa-4:run-2", "sa-4:run-3"]);

  const boundary = {
    ...customEntry("4", { version: 1 }),
    customType: SUBAGENT_RECOVERY_BOUNDARY_ENTRY_TYPE,
  };
  assert.equal(recoveryCheckpointsFromEntries([...entries, boundary]).size, 0);
  assert.deepEqual(
    [...recoveryPublicIdsFromEntries([...entries, boundary])],
    ["sa-4"],
  );
});

test("durable checkpoints seed exact pending completion identities", () => {
  const running = checkpointFromSnapshot(snapshot())!;
  const terminalPending = {
    ...checkpointFromSnapshot(snapshot({ id: "sa-5" }))!,
    status: "done" as const,
    delivery: "pending" as const,
  };
  const terminalSuppressed = {
    ...checkpointFromSnapshot(snapshot({ id: "sa-6" }))!,
    status: "error" as const,
    delivery: "suppressed" as const,
  };
  const legacyTerminal = {
    ...checkpointFromSnapshot(snapshot({ id: "sa-7" }))!,
    status: "done" as const,
    delivery: undefined,
  };
  assert.deepEqual(
    pendingRecoveryCompletionIdsFromEntries([
      customEntry("running", running),
      customEntry("pending", terminalPending),
      customEntry("suppressed", terminalSuppressed),
      customEntry("legacy-terminal", legacyTerminal),
      deliveredResult("delivered", "sa-5:run-2"),
    ]),
    ["sa-4:run-2"],
  );
});

test("recovery prompt preserves accepted but undelivered messages", () => {
  const prompt = buildSubagentRecoveryPrompt("original", [
    { text: "first guidance" },
    { text: "second guidance" },
  ]);
  assert.match(prompt, /Original task[\s\S]*original/);
  assert.match(prompt, /1\. first guidance[\s\S]*2\. second guidance/);
});

test("checkpoints preserve the selected model through serialization", () => {
  for (const model of [
    "openai-codex/gpt-5.6-sol",
    "openai-codex/gpt-6-astra",
  ]) {
    const checkpoint = checkpointFromSnapshot(
      snapshot({
        meta: {
          backend: "pi",
          sessionFilePath: "/sessions/child.jsonl",
          modelLabel: model,
        },
      }),
      "suspended",
    );
    assert.ok(checkpoint);
    const restored = parseRecoveryCheckpoint(
      JSON.parse(JSON.stringify(checkpoint)),
    );
    assert.equal(restored?.model, model);
    assert.equal(restored?.status, "suspended");
  }
  const legacy = checkpointFromSnapshot(snapshot());
  assert.ok(parseRecoveryCheckpoint(legacy));
  assert.equal(parseRecoveryCheckpoint(legacy)?.model, undefined);
  for (const model of [null, 42, "", "   "]) {
    assert.equal(parseRecoveryCheckpoint({ ...legacy, model }), undefined);
  }
});

test("malformed or future recovery records are ignored", () => {
  assert.equal(parseRecoveryCheckpoint(undefined), undefined);
  assert.equal(parseRecoveryCheckpoint({ version: 2 }), undefined);
  assert.equal(
    parseRecoveryCheckpoint({
      ...checkpointFromSnapshot(snapshot()),
      run: 0,
    }),
    undefined,
  );
  assert.equal(
    parseRecoveryCheckpoint({
      ...checkpointFromSnapshot(snapshot()),
      allowedSubagentsDepth: -1,
    }),
    undefined,
  );
});
