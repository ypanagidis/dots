/**
 * End-to-end smoke tests: manager behavior through a real ManagedRuntime,
 * exactly as the tool handlers drive it. The registry is test-only: scripted
 * stub sessions registered under the claude/codex names (the production
 * backends launch real processes and have their own live test files), plus
 * the real pi backend for its cheap registry precondition.
 */

import assert from "node:assert/strict";
import test from "node:test";
import { Effect, Layer, ManagedRuntime, Queue, Stream, type Cause } from "effect";
import {
  BackendRegistry,
  type SubagentBackend,
  type SubagentSession,
} from "./src/backend.ts";
import {
  childExcludedToolNames,
  piBackend,
  piTranscriptUserEvent,
  recoveredSessionNeedsContinuation,
  repairInterruptedToolCallMessages,
} from "./src/backends/pi.ts";
import { makeStubBackend } from "./src/backends/stub.ts";
import { SpawnError } from "./src/domain.ts";
import type {
  BackendName,
  ParentContext,
  SpawnTask,
  SubagentEvent,
} from "./src/domain.ts";
import {
  SubagentManager,
  SubagentManagerLive,
  type SubagentManagerShape,
} from "./src/manager.ts";
import {
  createSubagentRuntimeWithBackends,
  runTool,
} from "./src/runtime.ts";

const TestRegistryLive = Layer.sync(BackendRegistry, () => {
  const backends: SubagentBackend[] = [
    piBackend,
    makeStubBackend({
      backend: "claude",
      defaultModelLabel: "claude/sonnet",
      contextWindow: 200_000,
      toolName: "Bash",
      cadenceMs: 40,
    }),
    makeStubBackend({
      backend: "codex",
      defaultModelLabel: "codex/gpt-5-codex",
      contextWindow: 272_000,
      toolName: "shell",
      cadenceMs: 30,
    }),
  ];
  return new Map<BackendName, SubagentBackend>(
    backends.map((backend) => [backend.name, backend]),
  );
});

const createTestRuntime = () =>
  ManagedRuntime.make(
    SubagentManagerLive.pipe(Layer.provide(TestRegistryLive)),
  );

const parent: ParentContext = {
  parentCwd: process.cwd(),
  projectTrusted: false,
};

function task(prompt: string): SpawnTask {
  return { prompt, title: "test", cwd: process.cwd(), parent };
}

async function awaitSettled(
  manager: SubagentManagerShape,
  id: string,
  timeoutMs = 5_000,
) {
  const deadline = Date.now() + timeoutMs;
  while (manager.view.get(id)?.status === "running") {
    if (Date.now() >= deadline) throw new Error(`Timed out waiting for ${id}`);
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

async function withManager(
  run: (
    manager: SubagentManagerShape,
    runtime: ReturnType<typeof createTestRuntime>,
  ) => Promise<void>,
) {
  const runtime = createTestRuntime();
  try {
    const manager = await runtime.runPromise(SubagentManager);
    await run(manager, runtime);
  } finally {
    await runtime.dispose();
  }
}

test("stub subagent completes and delivers a final result", async () => {
  await withManager(async (manager, runtime) => {
    const settled: Array<{ id: string; consumed: boolean }> = [];
    manager.view.setOnSettled((snap, consumed) =>
      settled.push({ id: snap.id, consumed }),
    );

    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("Say hello to the tests")),
    );
    assert.equal(snap.status, "running");
    assert.equal(snap.backend, "claude");
    assert.ok(snap.meta.sessionFilePath);

    await awaitSettled(manager, snap.id);
    const done = manager.view.get(snap.id);
    assert.ok(done);
    assert.equal(done.status, "done");
    assert.equal(done.run, 1);
    assert.match(
      done.finalText,
      /\[stub:claude\] completed: Say hello to the tests/,
    );
    assert.ok(done.turns >= 2);
    assert.ok(done.transcript.some((item) => item.kind === "toolResult"));
    // Polling settlement never suppresses the normal completion callback.
    assert.deepEqual(settled, [{ id: snap.id, consumed: false }]);
  });
});

test("FAIL: prompts settle as errors; unconsumed settles are delivered", async () => {
  await withManager(async (manager, runtime) => {
    const settled: Array<{ id: string; consumed: boolean }> = [];
    manager.view.setOnSettled((snap, consumed) =>
      settled.push({ id: snap.id, consumed }),
    );

    const snap = await runTool(
      runtime,
      manager.spawn("codex", task("FAIL: blow up please")),
    );
    // Poll without wait-interest so the settle is delivered unconsumed.
    while (manager.view.get(snap.id)?.status === "running") {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    const failed = manager.view.get(snap.id);
    assert.equal(failed?.status, "error");
    assert.match(failed?.errorText ?? "", /task failed/);
    assert.deepEqual(settled, [{ id: snap.id, consumed: false }]);
  });
});

test("cancel interrupts a running stub subagent", async () => {
  await withManager(async (manager, runtime) => {
    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("Long running task")),
    );
    const report = await runTool(runtime, manager.cancel([snap.id]));
    assert.deepEqual(report, [
      {
        id: snap.id,
        title: "test",
        status: "error",
        cancelled: true,
        completionId: `${snap.id}:run-1`,
      },
    ]);
    assert.equal(manager.view.get(snap.id)?.errorText, "Run was aborted");
  });
});

test("spawn origin propagates to ids, snapshots, and settlement", async () => {
  await withManager(async (manager, runtime) => {
    const settled: Array<{ id: string; origin: string }> = [];
    manager.view.setOnSettled((snap) =>
      settled.push({ id: snap.id, origin: snap.origin }),
    );

    const model = await runTool(
      runtime,
      manager.spawn("codex", task("model task")),
    );
    const btw = await runTool(
      runtime,
      manager.spawn("claude", { ...task("side question"), origin: "btw" }),
    );

    assert.match(model.id, /^sa-/);
    assert.equal(model.origin, "model");
    assert.match(btw.id, /^btw-/);
    assert.equal(btw.origin, "btw");

    await runTool(runtime, manager.cancel([model.id, btw.id]));
    assert.deepEqual(
      settled.sort((a, b) => a.id.localeCompare(b.id)),
      [
        { id: btw.id, origin: "btw" },
        { id: model.id, origin: "model" },
      ].sort((a, b) => a.id.localeCompare(b.id)),
    );
  });
});

test("the global concurrency cap includes by-the-way sessions", async () => {
  await withManager(async (manager, runtime) => {
    const tasks: SpawnTask[] = [
      { ...task("side question"), origin: "btw" },
      task("Task 2"),
      task("Task 3"),
      task("Task 4"),
    ];
    const spawns = await runTool(
      runtime,
      Effect.forEach(tasks, (spawnTask) => manager.spawn("codex", spawnTask), {
        concurrency: "unbounded",
      }),
    );
    assert.equal(spawns.length, 4);
    await assert.rejects(
      runTool(
        runtime,
        manager.spawn("codex", {
          ...task("another side question"),
          origin: "btw",
        }),
      ),
      /Max 4 subagents/,
    );
  });
});

test("the concurrency cap rejects a fifth running subagent", async () => {
  await withManager(async (manager, runtime) => {
    const spawns = await runTool(
      runtime,
      Effect.forEach(
        [1, 2, 3, 4],
        (n) => manager.spawn("codex", task(`Task ${n}`)),
        { concurrency: "unbounded" },
      ),
    );
    assert.equal(spawns.length, 4);
    await assert.rejects(
      runTool(runtime, manager.spawn("codex", task("Task 5"))),
      /Max 4 subagents/,
    );
  });
});

test("recovery repairs unmatched child tool calls before continuation", () => {
  const assistant = {
    role: "assistant",
    content: [
      { type: "toolCall", id: "call-a", name: "bash", arguments: {} },
      { type: "toolCall", id: "call-b", name: "read", arguments: {} },
    ],
    stopReason: "toolUse",
  } as unknown as Parameters<typeof repairInterruptedToolCallMessages>[0][number];
  const resultA = {
    role: "toolResult",
    toolCallId: "call-a",
    toolName: "bash",
    content: [{ type: "text", text: "ok" }],
    isError: false,
    timestamp: 1,
  } as unknown as Parameters<typeof repairInterruptedToolCallMessages>[0][number];

  const repaired = repairInterruptedToolCallMessages([assistant, resultA]);
  assert.equal(repaired.syntheticCount, 1);
  assert.equal(repaired.trailingSynthetic.length, 1);
  assert.equal(repaired.trailingSynthetic[0]?.toolCallId, "call-b");
  assert.equal(repaired.trailingSynthetic[0]?.isError, true);
  assert.deepEqual(
    repaired.messages.map((message) => message.role),
    ["assistant", "toolResult", "toolResult"],
  );
});

test("recovery inserts historical synthetic results before a later user turn", () => {
  const assistant = {
    role: "assistant",
    content: [{ type: "toolCall", id: "call-a", name: "bash", arguments: {} }],
    stopReason: "toolUse",
  } as unknown as Parameters<typeof repairInterruptedToolCallMessages>[0][number];
  const user = {
    role: "user",
    content: "continue",
    timestamp: 2,
  } as unknown as Parameters<typeof repairInterruptedToolCallMessages>[0][number];

  const repaired = repairInterruptedToolCallMessages([assistant, user]);
  assert.equal(repaired.syntheticCount, 1);
  assert.equal(repaired.trailingSynthetic.length, 0);
  assert.deepEqual(
    repaired.messages.map((message) => message.role),
    ["assistant", "toolResult", "user"],
  );
});

test("recovery skips only a clean, fully settled durable child tail", () => {
  assert.equal(
    recoveredSessionNeedsContinuation({
      tailRole: "assistant",
      lastStopReason: "stop",
      interruptedToolCalls: 0,
      pendingBackgroundTasks: 0,
      queuedMessages: 0,
    }),
    false,
  );
  assert.equal(
    recoveredSessionNeedsContinuation({
      tailRole: "assistant",
      lastStopReason: "stop",
      interruptedToolCalls: 1,
      pendingBackgroundTasks: 0,
      queuedMessages: 0,
    }),
    true,
  );
  assert.equal(
    recoveredSessionNeedsContinuation({
      tailRole: "assistant",
      lastStopReason: "stop",
      interruptedToolCalls: 0,
      pendingBackgroundTasks: 1,
      queuedMessages: 0,
    }),
    true,
  );
  assert.equal(
    recoveredSessionNeedsContinuation({
      tailRole: "assistant",
      lastStopReason: "aborted",
      interruptedToolCalls: 0,
      pendingBackgroundTasks: 0,
      queuedMessages: 0,
    }),
    true,
  );
  assert.equal(
    recoveredSessionNeedsContinuation({
      tailRole: "user",
      lastStopReason: "stop",
      interruptedToolCalls: 0,
      pendingBackgroundTasks: 0,
      queuedMessages: 0,
    }),
    true,
  );
  assert.equal(
    recoveredSessionNeedsContinuation({
      tailRole: "assistant",
      lastStopReason: "stop",
      interruptedToolCalls: 0,
      pendingBackgroundTasks: 0,
      queuedMessages: 1,
    }),
    true,
  );
});

test("pi transcript preserves teamlead custom-message provenance", () => {
  assert.deepEqual(
    piTranscriptUserEvent({
      role: "custom",
      customType: "subagent-teamlead-guidance",
      content: "Inspect the parser boundary.",
    }),
    {
      _tag: "UserMessage",
      text: "Inspect the parser boundary.",
      source: "teamlead",
    },
  );
  assert.deepEqual(
    piTranscriptUserEvent({ role: "user", content: "Manual follow-up" }),
    {
      _tag: "UserMessage",
      text: "Manual follow-up",
      source: "user",
    },
  );
  assert.equal(
    piTranscriptUserEvent({
      role: "custom",
      customType: "background-completion-batch",
      content: "not a child prompt",
    }),
    undefined,
  );
});

test("positive descendant depth exposes only managed subagent orchestration", () => {
  assert.ok(childExcludedToolNames(0).includes("subagent_spawn"));
  assert.ok(childExcludedToolNames(0).includes("workflow"));
  assert.ok(!childExcludedToolNames(1).includes("subagent_spawn"));
  assert.ok(!childExcludedToolNames(3).includes("subagent_reply"));
  assert.ok(childExcludedToolNames(3).includes("workflow"));
  assert.ok(childExcludedToolNames(3).includes("ask_user"));
});

test("pi spawn fails fast without the parent model registry", async () => {
  await withManager(async (manager, runtime) => {
    await assert.rejects(
      runTool(runtime, manager.spawn("pi", task("needs a registry"))),
      /model registry/,
    );
    // The failed spawn must release its concurrency reservation.
    const snap = await runTool(runtime, manager.spawn("codex", task("ok")));
    assert.equal(snap.backend, "codex");
  });
});

test("idle restarts respect the concurrency cap", async () => {
  await withManager(async (manager, runtime) => {
    // Settle one subagent, then fill all four slots with running ones.
    const settled = await runTool(
      runtime,
      manager.spawn("claude", task("early finisher")),
    );
    await awaitSettled(manager, settled.id);
    await runTool(
      runtime,
      Effect.forEach(
        [1, 2, 3, 4],
        (n) => manager.spawn("codex", task(`Task ${n}`)),
        { concurrency: "unbounded" },
      ),
    );
    // Restarting the settled one would be a fifth concurrent run.
    await assert.rejects(
      runTool(runtime, manager.send(settled.id, "go again")),
      /Max 4 subagents/,
    );
    assert.equal(manager.view.get(settled.id)?.status, "done");
  });
});

test("concurrent sends share one settled restart slot", async () => {
  await withManager(async (manager, runtime) => {
    const settled = await runTool(
      runtime,
      manager.spawn("claude", task("settle first")),
    );
    await awaitSettled(manager, settled.id);
    const running = await runTool(
      runtime,
      Effect.forEach(
        [1, 2, 3],
        (n) => manager.spawn("codex", task(`running ${n}`)),
        { concurrency: "unbounded" },
      ),
    );

    const restartOrder: string[] = [];
    manager.view.setOnLifecycle((current) => {
      if (current.id === settled.id && current.run === 2) {
        restartOrder.push("checkpoint-run-2");
      }
    });
    const acceptances = await runTool(
      runtime,
      Effect.forEach(
        ["first restart message", "second restart message"],
        (message) => manager.message(settled.id, message),
        { concurrency: "unbounded" },
      ),
    );
    restartOrder.push("acceptance-returned");
    assert.deepEqual(restartOrder, [
      "checkpoint-run-2",
      "acceptance-returned",
    ]);
    assert.deepEqual(
      acceptances.map((acceptance) => ({
        startsNewRun: acceptance.startsNewRun,
        completionId: acceptance.completionId,
      })),
      [
        { startsNewRun: true, completionId: `${settled.id}:run-2` },
        { startsNewRun: true, completionId: `${settled.id}:run-2` },
      ],
    );

    while ((manager.view.get(settled.id)?.run ?? 0) < 2) {
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
    assert.equal(manager.view.get(settled.id)?.run, 2);
    await runTool(
      runtime,
      manager.cancel([settled.id, ...running.map((snap) => snap.id)]),
    );
  });
});

test("restart acceptance fails closed when its lifecycle checkpoint fails", async () => {
  await withManager(async (manager, runtime) => {
    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("settle before failed restart")),
    );
    await awaitSettled(manager, snap.id);
    manager.view.setOnLifecycle((current) => {
      if (current.id === snap.id && current.run === 2) {
        throw new Error("checkpoint failed");
      }
    });

    await assert.rejects(
      runTool(runtime, manager.message(snap.id, "restart")),
      /Could not persist.*run 2.*restart was aborted/i,
    );
    await awaitSettled(manager, snap.id);
    assert.equal(manager.view.get(snap.id)?.run, 2);
    assert.equal(manager.view.get(snap.id)?.status, "error");
  });
});

test("restart checkpoint failure aborts even after the requester is interrupted", async () => {
  let sendAccepted = false;
  const delayed: SubagentBackend = {
    name: "claude",
    capabilities: {
      steering: true,
      requestReply: false,
      modelSelection: false,
      reasoningEffort: false,
    },
    available: Effect.succeed(true),
    spawn: () =>
      Effect.gen(function* () {
        const events = yield* Queue.make<SubagentEvent, Cause.Done>();
        yield* Effect.addFinalizer(() => Queue.end(events).pipe(Effect.ignore));
        return {
          meta: Effect.succeed({
            backend: "claude",
            sessionFilePath: "/tmp/delayed-restart.jsonl",
          }),
          events: Stream.fromQueue(events),
          start: Effect.sync(() => {
            Queue.offerUnsafe(events, {
              _tag: "RunSettled",
              outcome: { _tag: "Completed", finalText: "initial done" },
            });
          }),
          send: () =>
            Effect.sync(() => {
              sendAccepted = true;
              setTimeout(() => {
                Queue.offerUnsafe(events, { _tag: "RunStarted" });
              }, 10);
            }),
          reply: () => Effect.void,
          interrupt: Effect.sync(() => {
            Queue.offerUnsafe(events, {
              _tag: "RunSettled",
              outcome: { _tag: "Interrupted" },
            });
          }),
        } satisfies SubagentSession;
      }),
  };
  const runtime = createSubagentRuntimeWithBackends([delayed]);
  try {
    const manager = await runtime.runPromise(SubagentManager);
    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("delayed restart")),
    );
    await awaitSettled(manager, snap.id);
    const settlements: Array<{ run: number; suppressed: boolean }> = [];
    manager.view.setOnSettled((current, suppressed) => {
      settlements.push({ run: current.run, suppressed });
    });
    manager.view.setOnLifecycle((current) => {
      if (current.run === 2) throw new Error("checkpoint failed");
    });

    const abortController = new AbortController();
    const sending = runTool(
      runtime,
      manager.message(snap.id, "restart later"),
      {
        signal: abortController.signal,
        interruptMessage: "Restart requester aborted.",
      },
    );
    while (!sendAccepted) {
      await new Promise((resolve) => setTimeout(resolve, 1));
    }
    abortController.abort();
    await assert.rejects(sending, /Restart requester aborted/);
    while (
      manager.view.get(snap.id)?.run !== 2 ||
      manager.view.get(snap.id)?.status === "running"
    ) {
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
    assert.equal(manager.view.get(snap.id)?.status, "error");
    assert.deepEqual(settlements, [{ run: 2, suppressed: true }]);
  } finally {
    await runtime.dispose();
  }
});

test("teamlead messages steer an idle subagent into another turn", async () => {
  await withManager(async (manager, runtime) => {
    const settledRuns: number[] = [];
    manager.view.setOnSettled((settled) => settledRuns.push(settled.run));
    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("First turn")),
    );
    await awaitSettled(manager, snap.id);
    const afterFirst = manager.view.get(snap.id);
    assert.equal(afterFirst?.status, "done");

    await runTool(runtime, manager.message(snap.id, "Second turn"));
    // The fresh run flips the status back to running...
    while (manager.view.get(snap.id)?.status !== "running") {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    await awaitSettled(manager, snap.id);
    const afterSecond = manager.view.get(snap.id);
    assert.equal(afterSecond?.status, "done");
    assert.equal(afterSecond?.run, 2);
    assert.match(afterSecond?.finalText ?? "", /Second turn/);
    assert.ok(
      afterSecond?.communications.some(
        (message) =>
          message.kind === "guidance" && message.text === "Second turn",
      ),
    );
    assert.ok(
      afterSecond?.transcript.some(
        (item) =>
          item.kind === "communication" &&
          item.message.kind === "guidance" &&
          item.message.text === "Second turn",
      ),
    );
    assert.ok(
      !afterSecond?.transcript.some(
        (item) => item.kind === "user" && item.text === "Second turn",
      ),
    );
    assert.deepEqual(settledRuns, [1, 2]);
  });
});

test("manual follow-ups remain ordinary user prompts", async () => {
  await withManager(async (manager, runtime) => {
    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("First turn")),
    );
    await awaitSettled(manager, snap.id);

    await runTool(runtime, manager.send(snap.id, "Follow-up aside"));
    while ((manager.view.get(snap.id)?.run ?? 0) < 2) {
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
    await awaitSettled(manager, snap.id);

    const done = manager.view.get(snap.id);
    assert.ok(
      done?.transcript.some(
        (item) => item.kind === "user" && item.text === "Follow-up aside",
      ),
    );
    assert.ok(
      !done?.communications.some(
        (message) =>
          message.kind === "guidance" && message.text === "Follow-up aside",
      ),
    );
  });
});

test("child update reaches the manager without blocking completion", async () => {
  await withManager(async (manager, runtime) => {
    const messages: string[] = [];
    manager.view.setOnMessage((_snap, message) => messages.push(message.text));

    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("UPDATE: Found an important issue")),
    );
    await awaitSettled(manager, snap.id);

    assert.deepEqual(messages, ["Found an important issue"]);
    assert.equal(manager.view.get(snap.id)?.status, "done");
  });
});

test("by-the-way sessions cannot publish teamlead communication", async () => {
  await withManager(async (manager, runtime) => {
    const messages: string[] = [];
    manager.view.setOnMessage((_snap, message) => messages.push(message.text));

    const snap = await runTool(
      runtime,
      manager.spawn("claude", {
        ...task("UPDATE: should stay private"),
        origin: "btw",
      }),
    );
    await awaitSettled(manager, snap.id);

    assert.deepEqual(messages, []);
  });
});

test("canceling a pending question publishes its resolution", async () => {
  await withManager(async (manager, runtime) => {
    const kinds: string[] = [];
    manager.view.setOnMessage((_snap, message) => kinds.push(message.kind));
    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("ASK: Need a decision")),
    );
    while ((manager.view.get(snap.id)?.pendingQuestions.length ?? 0) === 0) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }

    await runTool(runtime, manager.cancel([snap.id]));
    while (kinds.length < 2) {
      await new Promise((resolve) => setTimeout(resolve, 5));
    }

    assert.deepEqual(kinds, ["question", "resolution"]);
    assert.equal(manager.view.get(snap.id)?.pendingQuestions.length, 0);
  });
});

test("child question reaches the manager and a targeted reply resumes it", async () => {
  await withManager(async (manager, runtime) => {
    const messages: Array<{ id: string; requestId?: string }> = [];
    manager.view.setOnMessage((snap, message) => {
      messages.push({ id: snap.id, requestId: message.requestId });
    });

    const snap = await runTool(
      runtime,
      manager.spawn("claude", task("ASK: Should I continue?")),
    );
    while ((manager.view.get(snap.id)?.pendingQuestions.length ?? 0) === 0) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    const [question] = manager.view.get(snap.id)?.pendingQuestions ?? [];
    assert.ok(question);
    assert.deepEqual(messages, [{ id: snap.id, requestId: question.requestId }]);

    await runTool(
      runtime,
      manager.reply(snap.id, question.requestId, "Yes, continue."),
    );
    await awaitSettled(manager, snap.id);

    const done = manager.view.get(snap.id);
    assert.equal(done?.pendingQuestions.length, 0);
    assert.match(done?.finalText ?? "", /Teamlead replied: Yes, continue\./);
    assert.ok(
      done?.communications.some(
        (message) => message.kind === "reply" && /Yes, continue/.test(message.text),
      ),
    );
  });
});

test("the manager checkpoints a gated backend before initial work starts", async () => {
  const order: string[] = [];
  const gated: SubagentBackend = {
    name: "claude",
    capabilities: {
      steering: true,
      requestReply: false,
      modelSelection: false,
      reasoningEffort: false,
    },
    available: Effect.succeed(true),
    spawn: (spawnTask) =>
      Effect.gen(function* () {
        const events = yield* Queue.make<SubagentEvent, Cause.Done>();
        yield* Effect.addFinalizer(() => Queue.end(events).pipe(Effect.ignore));
        return {
          meta: Effect.succeed({
            backend: "claude",
            sessionFilePath: "/tmp/gated-child.jsonl",
          }),
          events: Stream.fromQueue(events),
          start: spawnTask.prompt === "fail gated start"
            ? Effect.fail(
                new SpawnError({ message: "extension bind failed" }),
              )
            : spawnTask.prompt === "block gated start"
              ? Effect.never
              : Effect.sync(() => {
                order.push("start");
                Queue.offerUnsafe(events, {
                  _tag: "RunSettled",
                  outcome: { _tag: "Completed", finalText: "done" },
                });
              }),
          send: () => Effect.void,
          reply: () => Effect.void,
          interrupt: Effect.void,
        } satisfies SubagentSession;
      }),
  };
  const registry = Layer.succeed(
    BackendRegistry,
    new Map<BackendName, SubagentBackend>([["claude", gated]]),
  );
  const runtime = ManagedRuntime.make(
    SubagentManagerLive.pipe(Layer.provide(registry)),
  );
  try {
    const manager = await runtime.runPromise(SubagentManager);
    manager.view.setOnLifecycle((snap) => {
      if (snap.status === "running") order.push("checkpoint");
    });
    const gatedSnap = await runTool(
      runtime,
      manager.spawn("claude", task("gated")),
    );
    assert.deepEqual(order.slice(0, 2), ["checkpoint", "start"]);
    await awaitSettled(manager, gatedSnap.id);

    const settled: Array<{ suppressed: boolean; error?: string }> = [];
    manager.view.setOnSettled((snap, suppressed) => {
      settled.push({ suppressed, error: snap.errorText });
    });
    const sizeBeforeFailedStart = manager.view.size();
    await assert.rejects(
      runTool(runtime, manager.spawn("claude", task("fail gated start"))),
      /extension bind failed/,
    );
    assert.equal(manager.view.size(), sizeBeforeFailedStart);
    assert.deepEqual(settled, [
      {
        suppressed: true,
        error: "Could not start subagent: extension bind failed",
      },
    ]);

    settled.length = 0;
    order.length = 0;
    const abortController = new AbortController();
    const blockedStart = runTool(
      runtime,
      manager.spawn("claude", task("block gated start")),
      {
        signal: abortController.signal,
        interruptMessage: "Gated start aborted.",
      },
    );
    while (!order.includes("checkpoint")) {
      await new Promise((resolve) => setTimeout(resolve, 1));
    }
    abortController.abort();
    await assert.rejects(blockedStart, /Gated start aborted/);
    assert.equal(manager.view.size(), sizeBeforeFailedStart);
    assert.deepEqual(settled, [
      { suppressed: true, error: "Subagent start was interrupted" },
    ]);

    order.length = 0;
    manager.view.setOnLifecycle(() => {
      order.push("checkpoint-failed");
      throw new Error("disk full");
    });
    await assert.rejects(
      runTool(runtime, manager.spawn("claude", task("must not start"))),
      /Could not persist the recovery checkpoint/,
    );
    assert.deepEqual(order, ["checkpoint-failed"]);
  } finally {
    await runtime.dispose();
  }
});

test("recovered spawns preserve public id, run, and creation time", async () => {
  await withManager(async (manager, runtime) => {
    const lifecycle: Array<{ id: string; run: number; status: string }> = [];
    manager.view.setOnLifecycle((snap) => {
      lifecycle.push({ id: snap.id, run: snap.run, status: snap.status });
    });

    const resumed = await runTool(
      runtime,
      manager.spawn("claude", {
        ...task("continue recovered work"),
        allowedSubagentsDepth: 2,
        resume: {
          id: "sa-9",
          sessionFilePath: "/tmp/existing-child.jsonl",
          run: 3,
          createdAt: 42,
        },
      }),
    );

    assert.equal(resumed.id, "sa-9");
    assert.equal(resumed.run, 3);
    assert.equal(resumed.createdAt, 42);
    assert.equal(resumed.allowedSubagentsDepth, 2);
    await awaitSettled(manager, resumed.id);
    assert.deepEqual(lifecycle[0], {
      id: "sa-9",
      run: 3,
      status: "running",
    });
    assert.deepEqual(lifecycle.at(-1), {
      id: "sa-9",
      run: 3,
      status: "done",
    });
    assert.ok(lifecycle.every((entry) => entry.id === "sa-9" && entry.run === 3));
  });
});

test("reserved recovery ids are not reused by fresh spawns", async () => {
  await withManager(async (manager, runtime) => {
    await runTool(runtime, manager.reserveIds(["sa-12", "btw-7", "invalid"]));

    const model = await runTool(runtime, manager.spawn("claude", task("model")));
    const btw = await runTool(
      runtime,
      manager.spawn("claude", { ...task("aside"), origin: "btw" }),
    );

    assert.equal(model.id, "sa-13");
    assert.equal(btw.id, "btw-8");
    await runTool(runtime, manager.cancel([model.id, btw.id]));
  });
});
