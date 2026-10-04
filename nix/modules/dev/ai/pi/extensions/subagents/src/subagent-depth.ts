import type { SessionEntry } from "@earendil-works/pi-coding-agent";

export const SUBAGENT_DEPTH_POLICY_ENTRY_TYPE = "subagent-depth-policy";
export const SUBAGENT_DEPTH_POLICY_VERSION = 1 as const;

export interface SubagentDepthPolicy {
  readonly version: typeof SUBAGENT_DEPTH_POLICY_VERSION;
  /** Number of additional managed descendant generations this session may create. */
  readonly allowedSubagentsDepth: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function isAllowedSubagentsDepth(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0
  );
}

export function parseSubagentDepthPolicy(
  value: unknown,
): SubagentDepthPolicy | undefined {
  if (
    !isRecord(value) ||
    value.version !== SUBAGENT_DEPTH_POLICY_VERSION ||
    !isAllowedSubagentsDepth(value.allowedSubagentsDepth)
  ) {
    return undefined;
  }
  return value as unknown as SubagentDepthPolicy;
}

/**
 * Return this session's inherited depth limit. A normal coordinator session has
 * no marker and is unrestricted. A marked but malformed child fails closed.
 */
export function subagentDepthLimitFromEntries(
  entries: ReadonlyArray<SessionEntry>,
): number | undefined {
  let depth: number | undefined;
  for (const entry of entries) {
    if (
      entry.type !== "custom" ||
      entry.customType !== SUBAGENT_DEPTH_POLICY_ENTRY_TYPE
    ) {
      continue;
    }
    const parsed = parseSubagentDepthPolicy(entry.data);
    if (!parsed) return 0;
    if (depth !== undefined && depth !== parsed.allowedSubagentsDepth) {
      return 0;
    }
    depth = parsed.allowedSubagentsDepth;
  }
  return depth;
}

/** Validate a requested child allowance against this session's inherited cap. */
export function validateRequestedSubagentDepth(
  requested: unknown,
  currentSessionLimit: number | undefined,
): number {
  if (!isAllowedSubagentsDepth(requested)) {
    throw new Error("allowed_subagents_depth must be a non-negative safe integer.");
  }
  if (
    currentSessionLimit !== undefined &&
    requested >= currentSessionLimit
  ) {
    if (currentSessionLimit === 0) {
      throw new Error("This subagent is not allowed to spawn managed descendants.");
    }
    throw new Error(
      `allowed_subagents_depth must be at most ${currentSessionLimit - 1} in this subagent session.`,
    );
  }
  return requested;
}

export function resolveSubagentSessionDepth(options: {
  readonly requestedDepth: unknown;
  readonly persistedDepth: number | undefined;
  readonly resuming: boolean;
}): number {
  const requestedDepth = validateRequestedSubagentDepth(
    options.requestedDepth,
    undefined,
  );
  if (
    options.resuming &&
    options.persistedDepth === undefined &&
    requestedDepth > 0
  ) {
    throw new Error(
      `Recovered subagent depth policy mismatch: parent checkpoint allows ${requestedDepth}, child session has no depth policy.`,
    );
  }
  if (
    options.resuming &&
    options.persistedDepth !== undefined &&
    options.persistedDepth !== requestedDepth
  ) {
    throw new Error(
      `Recovered subagent depth policy mismatch: parent checkpoint allows ${requestedDepth}, child session records ${options.persistedDepth}.`,
    );
  }
  return options.resuming
    ? (options.persistedDepth ?? requestedDepth)
    : requestedDepth;
}

export function createSubagentDepthPolicy(
  allowedSubagentsDepth: number,
): SubagentDepthPolicy {
  return {
    version: SUBAGENT_DEPTH_POLICY_VERSION,
    allowedSubagentsDepth: validateRequestedSubagentDepth(
      allowedSubagentsDepth,
      undefined,
    ),
  };
}
