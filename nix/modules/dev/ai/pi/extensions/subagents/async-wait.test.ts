import assert from "node:assert/strict";
import test from "node:test";
import { prepareAsyncWait } from "./src/async-wait.ts";
import type { SubagentSnapshot } from "./src/domain.ts";
import { createDeferredResultDelivery } from "./src/result-delivery.ts";

function snapshot(
  id: string,
  status: SubagentSnapshot["status"],
  run = 1,
): SubagentSnapshot {
  return {
    id,
    origin: "model",
    backend: "pi",
    title: id,
    prompt: "test",
    cwd: process.cwd(),
    allowedSubagentsDepth: 0,
    status,
    run,
    createdAt: Date.now(),
    meta: { backend: "pi" },
    usage: {},
    transcript: [],
    liveTools: [],
    queued: [],
    communications: [],
    pendingQuestions: [],
    finalText: status === "done" ? "finished" : "",
    turns: 0,
  };
}

test("async wait returns immediately and leaves running results for callbacks", () => {
  const delivery = createDeferredResultDelivery<SubagentSnapshot>(
    (snap) => `${snap.id}:run-${snap.run}`,
  );
  const running = snapshot("sa-1", "running");
  const startedAt = performance.now();

  const result = prepareAsyncWait([running], delivery);

  assert.ok(performance.now() - startedAt < 25);
  assert.deepEqual(result.details.pending, ["sa-1"]);
  assert.match(result.text, /Do not poll/);
  assert.deepEqual(delivery.drain(), []);
});

test("settled pending runs remain queued once, not duplicated", () => {
  const delivery = createDeferredResultDelivery<SubagentSnapshot>(
    (snap) => `${snap.id}:run-${snap.run}`,
  );
  const done = snapshot("sa-1", "done");
  delivery.defer(done);

  prepareAsyncWait([done], delivery);
  prepareAsyncWait([done], delivery);

  assert.deepEqual(delivery.drain().map((snap) => snap.id), ["sa-1"]);
});

test("async wait does not resurrect a cancellation-suppressed completion", () => {
  const delivery = createDeferredResultDelivery<SubagentSnapshot>(
    (snap) => `${snap.id}:run-${snap.run}`,
  );
  const cancelled = snapshot("sa-1", "error");
  delivery.suppress(cancelled);

  const result = prepareAsyncWait([cancelled], delivery);

  assert.equal(result.details.results[0]?.delivery, "suppressed");
  assert.deepEqual(delivery.drain(), []);
});
