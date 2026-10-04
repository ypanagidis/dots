import type { SessionEntry } from "@earendil-works/pi-coding-agent";
import type { SubagentSnapshot } from "./domain.ts";

export const SUBAGENT_RECOVERY_ENTRY_TYPE = "subagent-recovery";
export const SUBAGENT_RECOVERY_BOUNDARY_ENTRY_TYPE =
  "subagent-recovery-boundary";
export const SUBAGENT_RECOVERY_VERSION = 1 as const;

export type RecoveryCheckpointStatus =
  | "running"
  | "suspended"
  | "done"
  | "error";

/**
 * Durable parent-to-child link. The child JSONL remains the source of truth for
 * conversation history; this small parent-session record says which child file
 * belongs to which public subagent id and whether it still needs continuation.
 */
export interface SubagentRecoveryCheckpoint {
  readonly version: typeof SUBAGENT_RECOVERY_VERSION;
  readonly id: string;
  readonly origin: SubagentSnapshot["origin"];
  readonly title: string;
  readonly prompt: string;
  readonly cwd: string;
  /** Full provider/model id; old checkpoints used the fixed GPT-5.6 Sol model. */
  readonly model?: string;
  /** Omitted by checkpoints written before recursive delegation support. */
  readonly allowedSubagentsDepth?: number;
  readonly sessionFilePath: string;
  readonly run: number;
  readonly createdAt: number;
  readonly status: RecoveryCheckpointStatus;
  readonly settledAt?: number;
  readonly errorText?: string;
  /** Requests that cannot retain their in-process reply promises across restart. */
  readonly queued?: SubagentSnapshot["queued"];
  readonly pendingQuestions?: ReadonlyArray<{
    readonly requestId: string;
    readonly messageId: string;
    readonly question: string;
    readonly createdAt: number;
  }>;
  /** Bounded callback body retained until the parent records delivery. */
  readonly resultText?: string;
  /** Terminal callback state; omitted on old/running checkpoints. */
  readonly delivery?: "pending" | "suppressed";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isValidPublicId(value: string, origin: unknown): boolean {
  const match =
    origin === "model"
      ? /^sa-([1-9]\d*)$/.exec(value)
      : origin === "btw"
        ? /^btw-([1-9]\d*)$/.exec(value)
        : null;
  return match !== null && Number.isSafeInteger(Number(match[1]));
}

export function parseRecoveryCheckpoint(
  value: unknown,
): SubagentRecoveryCheckpoint | undefined {
  if (!isRecord(value) || value.version !== SUBAGENT_RECOVERY_VERSION) {
    return undefined;
  }
  if (
    typeof value.id !== "string" ||
    value.id.length > 32 ||
    (value.origin !== "model" && value.origin !== "btw") ||
    !isValidPublicId(value.id, value.origin) ||
    typeof value.title !== "string" ||
    typeof value.prompt !== "string" ||
    typeof value.cwd !== "string" ||
    (value.model !== undefined &&
      (typeof value.model !== "string" || value.model.trim().length === 0)) ||
    (value.allowedSubagentsDepth !== undefined &&
      (typeof value.allowedSubagentsDepth !== "number" ||
        !Number.isSafeInteger(value.allowedSubagentsDepth) ||
        value.allowedSubagentsDepth < 0)) ||
    typeof value.sessionFilePath !== "string" ||
    typeof value.run !== "number" ||
    !Number.isSafeInteger(value.run) ||
    value.run < 1 ||
    typeof value.createdAt !== "number" ||
    !Number.isFinite(value.createdAt) ||
    (value.status !== "running" &&
      value.status !== "suspended" &&
      value.status !== "done" &&
      value.status !== "error") ||
    (value.settledAt !== undefined &&
      (typeof value.settledAt !== "number" ||
        !Number.isFinite(value.settledAt))) ||
    (value.errorText !== undefined && typeof value.errorText !== "string") ||
    (value.queued !== undefined &&
      (!Array.isArray(value.queued) ||
        value.queued.some(
          (message) =>
            !isRecord(message) ||
            typeof message.text !== "string" ||
            (message.kind !== "steer" && message.kind !== "follow-up"),
        ))) ||
    (value.pendingQuestions !== undefined &&
      (!Array.isArray(value.pendingQuestions) ||
        value.pendingQuestions.some(
          (question) =>
            !isRecord(question) ||
            typeof question.requestId !== "string" ||
            typeof question.messageId !== "string" ||
            typeof question.question !== "string" ||
            typeof question.createdAt !== "number" ||
            !Number.isFinite(question.createdAt),
        ))) ||
    (value.resultText !== undefined && typeof value.resultText !== "string") ||
    (value.delivery !== undefined &&
      value.delivery !== "pending" &&
      value.delivery !== "suppressed")
  ) {
    return undefined;
  }
  // SAFETY: Every checkpoint field, including nested arrays and the optional
  // model id, was checked above. TypeScript cannot retain those array refinements.
  return value as unknown as SubagentRecoveryCheckpoint;
}

export function recoveryCompletionId(
  checkpoint: Pick<SubagentRecoveryCheckpoint, "id" | "run">,
): string {
  return `${checkpoint.id}:run-${checkpoint.run}`;
}

/**
 * Fold the active parent branch by completion identity. A later run must not
 * overwrite an older run whose terminal callback is still pending. A fork
 * boundary deliberately drops inherited ownership of every earlier child.
 */
export function recoveryCheckpointsFromEntries(
  entries: ReadonlyArray<SessionEntry>,
): ReadonlyMap<string, SubagentRecoveryCheckpoint> {
  const latest = new Map<string, SubagentRecoveryCheckpoint>();
  for (const entry of entries) {
    if (entry.type !== "custom") continue;
    if (entry.customType === SUBAGENT_RECOVERY_BOUNDARY_ENTRY_TYPE) {
      latest.clear();
      continue;
    }
    if (entry.customType !== SUBAGENT_RECOVERY_ENTRY_TYPE) continue;
    const checkpoint = parseRecoveryCheckpoint(entry.data);
    if (checkpoint) latest.set(recoveryCompletionId(checkpoint), checkpoint);
  }
  return latest;
}

/** Reserve public counters across boundaries so a fork does not reuse old ids. */
export function recoveryPublicIdsFromEntries(
  entries: ReadonlyArray<SessionEntry>,
): ReadonlySet<string> {
  const ids = new Set<string>();
  for (const entry of entries) {
    if (
      entry.type !== "custom" ||
      entry.customType !== SUBAGENT_RECOVERY_ENTRY_TYPE
    ) {
      continue;
    }
    const checkpoint = parseRecoveryCheckpoint(entry.data);
    if (checkpoint) ids.add(checkpoint.id);
  }
  return ids;
}

export function checkpointFromSnapshot(
  snapshot: SubagentSnapshot,
  status: RecoveryCheckpointStatus = snapshot.status,
): SubagentRecoveryCheckpoint | undefined {
  const sessionFilePath = snapshot.meta.sessionFilePath;
  if (!sessionFilePath) return undefined;
  return {
    version: SUBAGENT_RECOVERY_VERSION,
    id: snapshot.id,
    origin: snapshot.origin,
    title: snapshot.title,
    prompt: snapshot.prompt,
    cwd: snapshot.cwd,
    ...(snapshot.meta.modelLabel ? { model: snapshot.meta.modelLabel } : {}),
    allowedSubagentsDepth: snapshot.allowedSubagentsDepth,
    sessionFilePath,
    run: snapshot.run,
    createdAt: snapshot.createdAt,
    status,
    settledAt:
      status === "done" || status === "error" ? snapshot.settledAt : undefined,
    errorText: status === "error" ? snapshot.errorText : undefined,
    queued:
      snapshot.queued.length > 0
        ? snapshot.queued.map((message) => ({ ...message }))
        : undefined,
    pendingQuestions:
      snapshot.pendingQuestions.length > 0
        ? snapshot.pendingQuestions.map((question) => ({ ...question }))
        : undefined,
  };
}

export function isRecoverableCheckpoint(
  checkpoint: SubagentRecoveryCheckpoint,
): boolean {
  return checkpoint.status === "running" || checkpoint.status === "suspended";
}

/**
 * Seed lifecycle holds from durable child ownership, including the crash gap
 * before a subagent_spawn tool result could be appended to the transcript.
 * Replayed completion messages are applied before these IDs are seeded.
 */
export function pendingRecoveryCompletionIdsFromEntries(
  entries: ReadonlyArray<SessionEntry>,
): ReadonlyArray<string> {
  const delivered = new Set<string>();
  for (const entry of entries) {
    if (
      entry.type === "custom_message" &&
      entry.customType === "subagent-result"
    ) {
      const details = entry.details as { completionId?: unknown } | undefined;
      if (typeof details?.completionId === "string") {
        delivered.add(details.completionId);
      }
    }
  }
  return [...recoveryCheckpointsFromEntries(entries).values()]
    .filter((checkpoint) => {
      const completionId = recoveryCompletionId(checkpoint);
      return (
        !delivered.has(completionId) &&
        (isRecoverableCheckpoint(checkpoint) ||
          checkpoint.delivery === "pending")
      );
    })
    .map(recoveryCompletionId);
}

export function buildSubagentRecoveryPrompt(
  originalPrompt: string,
  queued: ReadonlyArray<{ readonly text: string }> = [],
): string {
  const queuedSection =
    queued.length > 0
      ? `\n\nThe following messages had been accepted but were not yet durably delivered. Incorporate them now, in order:\n\n${queued
          .map((message, index) => `${index + 1}. ${message.text}`)
          .join("\n")}`
      : "";
  return `The parent Pi process ended while you were working, and this child session has now been reopened from its last durable checkpoint. Continue the original task from the existing transcript and current workspace state.

Original task (also repeated here in case the process ended before the child JSONL's first durable assistant message):

${originalPrompt}${queuedSection}

First inspect what already completed. Do not blindly repeat side-effecting commands or assume an in-flight tool/process survived the restart. Re-run only the work that is still necessary, verify the final state, and end with the requested self-contained final response covering findings, changed files, verification, and blockers.`;
}
