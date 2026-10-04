export function createDeferredResultDelivery<T extends { id: string }>(
  keyOf: (result: T) => string = (result) => result.id,
) {
  const pending = new Map<string, T>();
  const emitted = new Set<string>();
  const emittedOrder: string[] = [];
  const suppressed = new Set<string>();
  const suppressedOrder: string[] = [];
  const rememberEmitted = (key: string) => {
    if (emitted.has(key)) return;
    emitted.add(key);
    emittedOrder.push(key);
    while (emittedOrder.length > 1_024) {
      const oldest = emittedOrder.shift();
      if (oldest) emitted.delete(oldest);
    }
  };

  const rememberSuppressed = (key: string) => {
    if (suppressed.has(key)) return;
    suppressed.add(key);
    suppressedOrder.push(key);
    while (suppressedOrder.length > 1_024) {
      const oldest = suppressedOrder.shift();
      if (oldest) suppressed.delete(oldest);
    }
  };

  return {
    defer(result: T) {
      const key = keyOf(result);
      if (!emitted.has(key) && !suppressed.has(key)) pending.set(key, result);
    },
    consume(results: Iterable<T>) {
      for (const result of results) pending.delete(keyOf(result));
    },
    suppress(result: T) {
      const key = keyOf(result);
      pending.delete(key);
      rememberSuppressed(key);
    },
    retry(result: T) {
      const key = keyOf(result);
      emitted.delete(key);
      const index = emittedOrder.indexOf(key);
      if (index >= 0) emittedOrder.splice(index, 1);
      suppressed.delete(key);
      const suppressedIndex = suppressedOrder.indexOf(key);
      if (suppressedIndex >= 0) suppressedOrder.splice(suppressedIndex, 1);
      pending.set(key, result);
    },
    state(result: T): "pending" | "emitted" | "suppressed" | "unknown" {
      const key = keyOf(result);
      if (pending.has(key)) return "pending";
      if (emitted.has(key)) return "emitted";
      if (suppressed.has(key)) return "suppressed";
      return "unknown";
    },
    drain() {
      const results = [...pending.values()];
      pending.clear();
      for (const result of results) rememberEmitted(keyOf(result));
      return results;
    },
    clear() {
      pending.clear();
      emitted.clear();
      emittedOrder.length = 0;
      suppressed.clear();
      suppressedOrder.length = 0;
    },
  };
}
