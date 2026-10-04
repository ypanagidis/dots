import assert from "node:assert/strict";
import test from "node:test";
import {
  BackgroundActivityTracker,
  completedBackgroundTaskIds,
  startedBackgroundTaskIds,
} from "./src/background-activity.ts";

const startedResult = (id = "bg_541b_mt2z3w44_1") => ({
  content: [
    {
      type: "text",
      text: `Started background process lifecycle test (${id}). Status: running. Log: /tmp/${id}.log`,
    },
  ],
});

test("callback-enabled background starts hold the managed run open", () => {
  assert.deepEqual(
    startedBackgroundTaskIds({
      toolName: "bg_task_spawn",
      args: { command: "sleep 120", callback: true },
      result: startedResult(),
      isError: false,
    }),
    ["bg_541b_mt2z3w44_1"],
  );
  assert.deepEqual(
    startedBackgroundTaskIds({
      toolName: "bg_task_spawn",
      args: { command: "server", callback: false },
      result: startedResult(),
      isError: false,
    }),
    [],
  );
  assert.deepEqual(
    startedBackgroundTaskIds({
      toolName: "bash",
      args: {},
      result: startedResult(),
      isError: false,
    }),
    [],
  );
});

test("completion batches and terminal status results release task IDs", () => {
  assert.deepEqual(
    completedBackgroundTaskIds({
      customType: "background-completion-batch",
      content:
        '1 background completion is ready:\n- source=background-task | id=bg_541b_mt2z3w44_1 | label="test" | status=succeeded | inspect: bg_task_status id=bg_541b_mt2z3w44_1',
    }),
    ["bg_541b_mt2z3w44_1"],
  );
  assert.deepEqual(
    completedBackgroundTaskIds({
      content: [
        {
          type: "text",
          text: "Background task bg_541b_mt2z3w44_1 (test) is failed.",
        },
      ],
    }),
    ["bg_541b_mt2z3w44_1"],
  );
});

test("tracker remains pending across idle turns until callback completion", () => {
  const tracker = new BackgroundActivityTracker();
  tracker.recordStarted({
    toolName: "bg_task_spawn",
    args: { command: "sleep 120", callback: true },
    result: startedResult(),
    isError: false,
  });
  assert.equal(tracker.pendingCount, 1);
  assert.deepEqual(tracker.pendingIds, ["bg_541b_mt2z3w44_1"]);

  // An ordinary assistant turn (for example replying to "hi") does not alter
  // the tracker, so the manager must still consider the logical run active.
  assert.equal(tracker.pendingCount, 1);

  tracker.recordCompleted({
    customType: "background-completion-batch",
    content:
      "- source=background-task | id=bg_541b_mt2z3w44_1 | status=succeeded",
  });
  assert.equal(tracker.pendingCount, 0);
});

test("nested subagent runs hold their parent run until callback or cancellation", () => {
  const tracker = new BackgroundActivityTracker();
  const spawnResult = {
    content: [{ type: "text", text: "Spawned subagent sa-1." }],
    details: { id: "sa-1", completionId: "sa-1:run-1" },
  };
  assert.deepEqual(
    startedBackgroundTaskIds({
      toolName: "subagent_spawn",
      args: { prompt: "work" },
      result: spawnResult,
      isError: false,
    }),
    ["subagent:sa-1:run-1"],
  );
  tracker.recordStarted({
    toolName: "subagent_spawn",
    args: { prompt: "work" },
    result: spawnResult,
    isError: false,
  });
  assert.deepEqual(tracker.pendingIds, ["subagent:sa-1:run-1"]);

  tracker.recordCompleted({
    customType: "subagent-result",
    content: "Subagent sa-1 finished.",
    details: { id: "sa-1", completionId: "sa-1:run-1" },
  });
  assert.equal(tracker.pendingCount, 0);

  tracker.recordStarted({
    toolName: "subagent_send",
    args: { id: "sa-2", message: "continue" },
    result: {
      details: {
        id: "sa-2",
        startsNewRun: true,
        completionId: "sa-2:run-2",
      },
    },
    isError: false,
  });
  assert.deepEqual(tracker.pendingIds, ["subagent:sa-2:run-2"]);
  tracker.recordCompleted({
    details: {
      results: [
        {
          id: "sa-2",
          status: "error",
          cancelled: true,
          completionId: "sa-2:run-2",
        },
      ],
    },
  });
  assert.equal(tracker.pendingCount, 0);
});

test("successive and overlapping nested runs are tracked by completion identity", () => {
  const tracker = new BackgroundActivityTracker();
  tracker.recordCompleted({
    customType: "subagent-result",
    details: { completionId: "sa-1:run-1" },
  });
  tracker.recordStarted({
    toolName: "subagent_send",
    args: { id: "sa-1" },
    result: {
      details: {
        startsNewRun: true,
        completionId: "sa-1:run-2",
      },
    },
    isError: false,
  });
  tracker.reconcilePendingSubagents(["sa-1:run-2", "sa-2:run-3"]);
  assert.deepEqual([...tracker.pendingIds].sort(), [
    "subagent:sa-1:run-2",
    "subagent:sa-2:run-3",
  ]);

  tracker.recordCompleted({
    customType: "subagent-result",
    details: { completionId: "sa-2:run-3" },
  });
  assert.deepEqual(tracker.pendingIds, ["subagent:sa-1:run-2"]);
  tracker.reconcilePendingSubagents([]);
  assert.equal(tracker.pendingCount, 0);
});

test("messages to already-running nested subagents do not create duplicate holds", () => {
  assert.deepEqual(
    startedBackgroundTaskIds({
      toolName: "subagent_send",
      args: { id: "sa-2", message: "guidance" },
      result: {
        details: {
          id: "sa-2",
          startsNewRun: false,
          completionId: undefined,
        },
      },
      isError: false,
    }),
    [],
  );
});

test("completion-before-start races and cancellation cannot resurrect a hold", () => {
  const tracker = new BackgroundActivityTracker();
  const completion = {
    customType: "background-completion-batch",
    content:
      "- source=background-task | id=bg_fast_1 | status=succeeded",
  };
  tracker.recordCompleted(completion);
  tracker.recordStarted({
    toolName: "bg_task_spawn",
    args: { callback: true },
    result: startedResult("bg_fast_1"),
    isError: false,
  });
  assert.equal(tracker.pendingCount, 0);

  tracker.recordStarted({
    toolName: "bg_task_watch",
    args: { callback: true },
    result: startedResult("bg_watch_2"),
    isError: false,
  });
  assert.equal(tracker.pendingCount, 1);
  tracker.cancelPending();
  assert.equal(tracker.pendingCount, 0);
  tracker.recordStarted({
    toolName: "bg_task_watch",
    args: { callback: true },
    result: startedResult("bg_watch_2"),
    isError: false,
  });
  assert.equal(tracker.pendingCount, 0);
});
