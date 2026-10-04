/**
 * Layer composition and the async entry-point boundary.
 *
 * Everything inside the extension is Effect generators; this module is where
 * tool handlers (plain async functions) run those effects against one shared
 * ManagedRuntime.
 */

import { Cause, Exit, Layer, ManagedRuntime, type Effect } from "effect";
import { BackendRegistry, type SubagentBackend } from "./backend.ts";
import { piBackend } from "./backends/pi.ts";
import type { BackendName } from "./domain.ts";

import { SubagentManagerLive } from "./manager.ts";

export function createSubagentRuntimeWithBackends(
  backends: ReadonlyArray<SubagentBackend>,
) {
  const registry = Layer.sync(BackendRegistry, () =>
    new Map<BackendName, SubagentBackend>(
      backends.map((backend) => [backend.name, backend]),
    ),
  );
  return ManagedRuntime.make(SubagentManagerLive.pipe(Layer.provide(registry)));
}

/** Production remains deliberately Pi-only. */
export function createSubagentRuntime() {
  return createSubagentRuntimeWithBackends([piBackend]);
}

export type SubagentRuntime = ReturnType<typeof createSubagentRuntime>;

/**
 * Run an effect from an async tool handler. Typed failures and defects are
 * converted to thrown Errors (what pi's tool contract expects); interruption
 * (tool AbortSignal) throws `interruptMessage`.
 */
export async function runTool<A, E>(
  runtime: SubagentRuntime,
  effect: Effect.Effect<A, E>,
  options: { signal?: AbortSignal; interruptMessage?: string } = {},
) {
  const exit = await runtime.runPromiseExit(
    effect,
    options.signal ? { signal: options.signal } : undefined,
  );
  if (Exit.isSuccess(exit)) return exit.value;
  if (Cause.hasInterruptsOnly(exit.cause)) {
    throw new Error(options.interruptMessage ?? "Operation was aborted.");
  }
  const [first] = Cause.prettyErrors(exit.cause);
  throw new Error(first?.message ?? Cause.pretty(exit.cause));
}
