import assert from "node:assert/strict";
import test from "node:test";
import {
  CommunicationError,
  appendBoundedCommunication,
  createCommunicationIdFactory,
  createPendingQuestionRegistry,
  createUpdateCommunication,
  validateCommunicationText,
  type CommunicationErrorCode,
  type SubagentCommunication,
} from "./src/communication.ts";

class ManualScheduler {
  readonly callbacks = new Map<number, () => void>();
  readonly canceled = new Set<number>();
  #next = 1;

  schedule(callback: () => void, _delayMs: number): number {
    const handle = this.#next++;
    this.callbacks.set(handle, callback);
    return handle;
  }

  cancel(handle: unknown): void {
    this.canceled.add(handle as number);
  }

  /** Simulates a timer callback already queued when cancellation occurred. */
  fire(handle = 1): void {
    this.callbacks.get(handle)?.();
  }
}

function throwsCode(operation: () => unknown, code: CommunicationErrorCode) {
  assert.throws(operation, (error) => {
    assert.ok(error instanceof CommunicationError);
    assert.equal(error.code, code);
    return true;
  });
}

function rejectsCode(promise: Promise<unknown>, code: CommunicationErrorCode) {
  return assert.rejects(promise, (error) => {
    assert.ok(error instanceof CommunicationError);
    assert.equal(error.code, code);
    return true;
  });
}

test("ID allocation is opaque, stable, unique, and constant-space", () => {
  let namespaceCalls = 0;
  const ids = createCommunicationIdFactory(() => {
    namespaceCalls += 1;
    return "session";
  });

  const first = ids.nextRequestId();
  const second = ids.nextRequestId();
  const message = ids.nextMessageId();

  assert.equal(first, "req-session-1");
  assert.equal(second, "req-session-2");
  assert.equal(message, "msg-session-1");
  assert.notEqual(first, second);
  assert.equal(namespaceCalls, 1);
  // IDs are plain immutable values: retaining an ID never changes it.
  assert.equal(first, "req-session-1");
  throwsCode(() => createCommunicationIdFactory(() => "  "), "id-collision");
});

test("text bounds use UTF-8 bytes, preserve exact text, and reject blanks", () => {
  assert.equal(validateCommunicationText("  exact reply  ", 20), "  exact reply  ");
  assert.equal(validateCommunicationText("😀", 4), "😀");
  throwsCode(() => validateCommunicationText("😀", 3), "text-too-large");
  throwsCode(() => validateCommunicationText(" \n\t "), "blank-text");
  assert.throws(() => validateCommunicationText("text", 0), RangeError);
});

test("updates share stable IDs and body validation with questions", () => {
  let counter = 0;
  const ids = createCommunicationIdFactory(() => `id-${++counter}`);
  const update = createUpdateCommunication("material finding", ids, {
    now: () => 42,
  });
  const registry = createPendingQuestionRegistry({
    ids,
    scheduler: new ManualScheduler(),
  });
  const question = registry.ask("decision?");

  assert.deepEqual(update, {
    messageId: "msg-id-1-1",
    kind: "update",
    text: "material finding",
    createdAt: 42,
  });
  assert.notEqual(update.messageId, question.communication.messageId);
  registry.cancel(question.communication.requestId);
  void question.result.catch(() => undefined);
});

test("a matching reply resolves exactly once and clears the pending question", async () => {
  let tick = 100;
  const registry = createPendingQuestionRegistry({
    now: () => tick++,
    scheduler: new ManualScheduler(),
  });
  const pending = registry.ask("Need a decision?");
  const { requestId } = pending.communication;

  assert.equal(registry.size, 1);
  assert.equal(registry.state(requestId), "pending");
  assert.deepEqual(registry.pending(), [pending.communication]);

  const reply = registry.reply(requestId, "  Keep this exact  ");
  assert.equal(await pending.result, "  Keep this exact  ");
  assert.equal(reply.kind, "reply");
  assert.equal(reply.requestId, requestId);
  assert.equal(reply.text, "  Keep this exact  ");
  assert.notEqual(reply.messageId, pending.communication.messageId);
  assert.equal(registry.size, 0);
  assert.equal(registry.state(requestId), "answered");
  throwsCode(() => registry.reply(requestId, "again"), "already-answered");
});

test("unknown and mismatched request IDs fail without disturbing the real ask", async () => {
  const registry = createPendingQuestionRegistry({
    scheduler: new ManualScheduler(),
  });
  const pending = registry.ask("Question");

  throwsCode(() => registry.reply("req-from-another-child", "no"), "unknown-request");
  assert.equal(registry.state(pending.communication.requestId), "pending");
  registry.reply(pending.communication.requestId, "yes");
  assert.equal(await pending.result, "yes");
});

test("reply wins a timeout race, including an already-queued timer callback", async () => {
  const scheduler = new ManualScheduler();
  const registry = createPendingQuestionRegistry({ scheduler, timeoutMs: 10 });
  const pending = registry.ask("Race?");

  registry.reply(pending.communication.requestId, "reply won");
  scheduler.fire();

  assert.equal(await pending.result, "reply won");
  assert.equal(registry.state(pending.communication.requestId), "answered");
});

test("timeout wins a race and a late reply reports an actionable error", async () => {
  const scheduler = new ManualScheduler();
  const registry = createPendingQuestionRegistry({ scheduler, timeoutMs: 10 });
  const pending = registry.ask("Race?");
  const rejection = rejectsCode(pending.result, "timed-out");

  scheduler.fire();
  await rejection;

  assert.equal(registry.state(pending.communication.requestId), "timed-out");
  throwsCode(
    () => registry.reply(pending.communication.requestId, "too late"),
    "timed-out",
  );
});

test("abort is first-wins and removes its listener/timer", async () => {
  const scheduler = new ManualScheduler();
  const controller = new AbortController();
  const registry = createPendingQuestionRegistry({ scheduler });
  const pending = registry.ask("Continue?", { signal: controller.signal });
  const rejection = rejectsCode(pending.result, "canceled");

  controller.abort();
  scheduler.fire();
  await rejection;

  assert.equal(registry.state(pending.communication.requestId), "canceled");
  assert.equal(registry.size, 0);
  throwsCode(
    () => registry.reply(pending.communication.requestId, "late"),
    "canceled",
  );
});

test("close rejects all asks, is idempotent, and prevents future traffic", async () => {
  const registry = createPendingQuestionRegistry({
    scheduler: new ManualScheduler(),
  });
  const one = registry.ask("One?");
  const two = registry.ask("Two?");
  const rejected = [
    rejectsCode(one.result, "closed"),
    rejectsCode(two.result, "closed"),
  ];

  registry.close("Session shutdown");
  registry.close("ignored second close");
  await Promise.all(rejected);

  assert.equal(registry.isClosed, true);
  assert.equal(registry.size, 0);
  assert.equal(registry.state(one.communication.requestId), "closed");
  throwsCode(() => registry.ask("new"), "closed");
  throwsCode(
    () => registry.reply(one.communication.requestId, "late"),
    "closed",
  );
});

test("pending requests and retained terminal states are bounded", async () => {
  const registry = createPendingQuestionRegistry({
    scheduler: new ManualScheduler(),
    maxPending: 1,
    settledHistoryLimit: 1,
  });
  const first = registry.ask("First?");
  throwsCode(() => registry.ask("Second?"), "too-many-pending");
  registry.reply(first.communication.requestId, "done");
  await first.result;

  const second = registry.ask("Second?");
  registry.reply(second.communication.requestId, "done too");
  await second.result;

  assert.equal(registry.state(first.communication.requestId), "unknown");
  assert.equal(registry.state(second.communication.requestId), "answered");
});

test("communication history retains only the newest configured entries", () => {
  const item = (messageId: string): SubagentCommunication => ({
    messageId,
    kind: "update",
    text: messageId,
    createdAt: 0,
  });
  let history: ReadonlyArray<SubagentCommunication> = [];
  history = appendBoundedCommunication(history, item("m1"), 2);
  history = appendBoundedCommunication(history, item("m2"), 2);
  history = appendBoundedCommunication(history, item("m3"), 2);

  assert.deepEqual(
    history.map(({ messageId }) => messageId),
    ["m2", "m3"],
  );
  assert.deepEqual(appendBoundedCommunication(history, item("m4"), 1), [
    item("m4"),
  ]);
  assert.deepEqual(appendBoundedCommunication(history, item("m4"), 0), []);
});
