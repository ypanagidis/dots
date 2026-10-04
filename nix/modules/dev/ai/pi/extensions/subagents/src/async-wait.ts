import {
  subagentCompletionId,
  type SubagentSnapshot,
} from "./domain.ts";

export type CompletionDeliveryState =
  | "pending"
  | "emitted"
  | "suppressed"
  | "unknown";

interface CompletionDelivery {
  state(snapshot: SubagentSnapshot): CompletionDeliveryState;
}

/**
 * Prepare the immediate result of model-facing subagent_wait.
 *
 * This function is intentionally synchronous: completion is always delivered
 * later through the normal per-run callback channel, never through an open
 * tool promise.
 */
export function prepareAsyncWait(
  snapshots: ReadonlyArray<SubagentSnapshot>,
  delivery: CompletionDelivery,
) {
  const ids = snapshots.map((snap) => snap.id);
  const pending = snapshots
    .filter((snap) => snap.status === "running")
    .map((snap) => snap.id);
  const results = snapshots.map((snap) => ({
    id: snap.id,
    title: snap.title,
    run: snap.run,
    completionId: subagentCompletionId(snap),
    status: snap.status,
    delivery: delivery.state(snap),
  }));
  const statusLines = results.map((result) => {
    const status =
      result.status === "running"
        ? "callback pending settlement"
        : result.delivery === "pending"
          ? "callback queued"
          : result.delivery === "emitted"
            ? "callback already emitted"
            : result.delivery === "suppressed"
              ? "callback suppressed by cancellation"
              : "callback state unavailable";
    return `- ${result.id} run ${result.run}: ${result.status} (${status})`;
  });

  return {
    text: [
      `Waiting asynchronously for ${ids.join(", ")}.`,
      `Pending: ${pending.join(", ") || "none"}.`,
      "Each subagent will deliver its final message separately. Do not poll or call subagent_wait repeatedly.",
      "Continue useful independent work; if none remains, give the user a concise delegation update and end this turn.",
      "",
      ...statusLines,
    ].join("\n"),
    details: { async: true as const, ids, pending, results },
  };
}
