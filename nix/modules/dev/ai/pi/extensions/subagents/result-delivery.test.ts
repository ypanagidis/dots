import assert from "node:assert/strict";
import test from "node:test";
import { createDeferredResultDelivery } from "./src/result-delivery.ts";

test("a result consumed before delivery is not emitted", () => {
  const delivery = createDeferredResultDelivery<{
    id: string;
    output: string;
  }>();
  const result = { id: "sa-1", output: "done" };

  delivery.defer(result);
  delivery.consume([result]);

  assert.deepEqual(delivery.drain(), []);
});

test("unconsumed results are delivered once in settlement order", () => {
  const delivery = createDeferredResultDelivery<{ id: string }>();
  const first = { id: "sa-1" };
  const second = { id: "sa-2" };

  delivery.defer(first);
  delivery.defer(second);

  assert.deepEqual(delivery.drain(), [first, second]);
  assert.deepEqual(delivery.drain(), []);
  assert.equal(delivery.state(first), "emitted");
});

test("suppressed completions cannot be re-deferred accidentally", () => {
  const delivery = createDeferredResultDelivery<{ id: string }>();
  const result = { id: "sa-1" };
  delivery.suppress(result);
  delivery.defer(result);

  assert.equal(delivery.state(result), "suppressed");
  assert.deepEqual(delivery.drain(), []);
});

test("a synchronous delivery failure can requeue the same completion", () => {
  const delivery = createDeferredResultDelivery<{ id: string }>();
  const result = { id: "sa-1" };
  delivery.defer(result);
  assert.deepEqual(delivery.drain(), [result]);

  delivery.retry(result);

  assert.equal(delivery.state(result), "pending");
  assert.deepEqual(delivery.drain(), [result]);
});

test("successive runs for one subagent do not overwrite each other", () => {
  const delivery = createDeferredResultDelivery<{ id: string; run: number }>(
    (result) => `${result.id}:run-${result.run}`,
  );
  const first = { id: "sa-1", run: 1 };
  const second = { id: "sa-1", run: 2 };

  delivery.defer(first);
  delivery.defer(second);

  assert.deepEqual(delivery.drain(), [first, second]);
});
