/**
 * SubagentManager — owns the registry of running/finished subagents.
 *
 * Each subagent is a scoped `SubagentSession` from a `SubagentBackend` plus a
 * pump fiber that folds its normalized event stream into a mutable
 * `SubagentSnapshot`. Closing a subagent's scope kills the underlying
 * session/process and stops the pump.
 *
 * The manager also exposes a synchronous `SubagentReadModel` so the
 * imperative TUI components (which render synchronously) can read snapshots
 * and issue fire-and-forget commands without touching the Effect runtime.
 */

import {
  Context,
  Effect,
  Exit,
  Fiber,
  Layer,
  Result,
  Scope,
  Stream,
} from "effect";
import type { SubagentBackend, SubagentSession } from "./backend.ts";
import { validateCommunicationText } from "./communication.ts";
import { BackendRegistry } from "./backend.ts";
import type {
  BackendName,
  LiveToolState,
  RunOutcome,
  SpawnTask,
  SubagentCommunication,
  SubagentEvent,
  SubagentInputSource,
  SubagentOrigin,
  SubagentMeta,
  SubagentSnapshot,
  SubagentStatus,
  TranscriptItem,
} from "./domain.ts";
import {
  BackendUnavailableError,
  ConcurrencyLimitError,
  ReplyError,
  SendError,
  subagentCompletionId,
  SpawnError,
} from "./domain.ts";

export const MAX_RUNNING = 4;
export const MAX_TRACKED = 64;
const STOP_TIMEOUT_MS = 5_000;
const ERROR_TEXT_MAX_LENGTH = 4_096;
const TRANSCRIPT_TEXT_MAX_LENGTH = 64 * 1_024;
const LIVE_ASSISTANT_MAX_LENGTH = 128 * 1_024;
const FINAL_TEXT_MAX_LENGTH = 1_024 * 1_024;
const MAX_TRANSCRIPT_ITEMS = 512;
const MAX_COMMUNICATION_ITEMS = 128;

function bounded(text: string) {
  return text.slice(0, ERROR_TEXT_MAX_LENGTH);
}

function boundedTranscriptText(text: string) {
  return text.slice(0, TRANSCRIPT_TEXT_MAX_LENGTH);
}

function appendTranscript(snapshot: MutableSnapshot, item: TranscriptItem) {
  snapshot.transcript.push(item);
  if (snapshot.transcript.length > MAX_TRANSCRIPT_ITEMS) {
    snapshot.transcript.splice(
      0,
      snapshot.transcript.length - MAX_TRANSCRIPT_ITEMS,
    );
  }
}

// --- Internal state -----------------------------------------------------------

/** Mutable snapshot; exposed to readers via the readonly SubagentSnapshot type. */
interface MutableSnapshot {
  id: string;
  origin: SubagentOrigin;
  backend: BackendName;
  title: string;
  prompt: string;
  cwd: string;
  allowedSubagentsDepth: number;
  status: SubagentStatus;
  run: number;
  createdAt: number;
  settledAt?: number;
  errorText?: string;
  meta: SubagentMeta;
  usage: { tokens?: number; contextWindow?: number };
  transcript: TranscriptItem[];
  liveAssistant?: { text: string; thinking: string };
  liveTools: LiveToolState[];
  queued: SubagentSnapshot["queued"];
  communications: SubagentCommunication[];
  pendingQuestions: SubagentSnapshot["pendingQuestions"];
  finalText: string;
  turns: number;
}

interface Entry {
  snapshot: MutableSnapshot;
  session: SubagentSession;
  scope: Scope.Closeable;
  pump?: Fiber.Fiber<void>;
  liveToolMap: Map<string, LiveToolState>;
  /** Idle restart dispatched but RunStarted not folded yet; counts as running
   * so concurrent restarts cannot race past the cap. */
  restarting?: boolean;
  /** Restart run whose lifecycle checkpoint failed; acceptance must fail/abort. */
  restartCheckpointErrorRun?: number;
}

// --- Read model ----------------------------------------------------------------

/** Synchronous bridge for the TUI. Snapshots are live objects; do not mutate. */
export interface SubagentReadModel {
  list(): ReadonlyArray<SubagentSnapshot>;
  get(id: string): SubagentSnapshot | undefined;
  size(): number;
  /** Any-change notification (footer status, dashboard). */
  subscribe(listener: () => void): () => void;
  /** Per-subagent notification (takeover view). */
  subscribeTo(id: string, listener: () => void): () => void;
  /** Fire-and-forget: steer/continue a subagent (takeover input). */
  requestSend(id: string, text: string): void;
  /** Fire-and-forget: abort a running subagent (dashboard `x`, takeover). */
  requestAbort(id: string): void;
  /** Register the settle hook. `suppressed` is true for tool-driven cancel. */
  setOnSettled(
    hook: ((snap: SubagentSnapshot, suppressed: boolean) => void) | undefined,
  ): void;
  /** Register delivery of child updates/questions to the parent extension. */
  setOnMessage(
    hook:
      | ((snap: SubagentSnapshot, message: SubagentCommunication) => void)
      | undefined,
  ): void;
  /** Register durable lifecycle checkpointing (spawn/restart/settle). */
  setOnLifecycle(
    hook: ((snap: SubagentSnapshot) => void) | undefined,
  ): void;
}

// --- Service --------------------------------------------------------------------

export interface MessageAcceptance {
  readonly startsNewRun: boolean;
  readonly completionId?: string;
  readonly statusAtAcceptance: SubagentStatus;
  readonly runAtAcceptance: number;
}

export interface CancelResult {
  readonly id: string;
  readonly title: string;
  readonly status: SubagentStatus;
  readonly cancelled: boolean;
  readonly completionId?: string;
}

export interface SubagentManagerShape {
  spawn(
    backend: BackendName,
    task: SpawnTask,
  ): Effect.Effect<
    SubagentSnapshot,
    SpawnError | ConcurrencyLimitError | BackendUnavailableError
  >;
  /** Cancel running subagents; resolves when they have settled. */
  cancel(
    ids: ReadonlyArray<string>,
  ): Effect.Effect<ReadonlyArray<CancelResult>>;
  /** Model-facing/teamlead message path. */
  message(
    id: string,
    text: string,
  ): Effect.Effect<MessageAcceptance, SendError>;
  /** Takeover compatibility alias with the same steer-or-restart semantics. */
  send(id: string, text: string): Effect.Effect<void, SendError>;
  reply(
    id: string,
    requestId: string,
    text: string,
  ): Effect.Effect<void, ReplyError>;
  get(id: string): Effect.Effect<SubagentSnapshot | undefined>;
  readonly list: Effect.Effect<ReadonlyArray<SubagentSnapshot>>;
  /** Prevent restored/settled ids from being reused by later fresh spawns. */
  reserveIds(ids: ReadonlyArray<string>): Effect.Effect<void>;
  readonly disposeAll: Effect.Effect<void>;
  readonly view: SubagentReadModel;
}

export class SubagentManager extends Context.Service<
  SubagentManager,
  SubagentManagerShape
>()("subagents/SubagentManager") {}

// --- Implementation --------------------------------------------------------------

const makeManager = Effect.gen(function* () {
  const registry = yield* BackendRegistry;
  // Detached forker for sync contexts (read-model commands, pruning) that
  // preserves the manager's services instead of using the global runtime.
  const runDetached = Effect.runForkWith(yield* Effect.context());

  const entries = new Map<string, Entry>();
  const suppressedCompletions = new Map<string, number>();
  const listeners = new Set<() => void>();
  /** One-shot nextChange waiters, swapped out before invocation so waiters
   * re-registering during notification are not visited in the same sweep. */
  let changeWaiters: Array<() => void> = [];
  const idListeners = new Map<string, Set<() => void>>();
  const cleanups = new Set<Fiber.Fiber<unknown>>();
  let modelCounter = 0;
  let btwCounter = 0;
  let teamleadMessageCounter = 0;
  let reserved = 0;
  let disposed = false;
  let onSettled:
    ((snap: SubagentSnapshot, suppressed: boolean) => void) | undefined;
  let onMessage:
    | ((snap: SubagentSnapshot, message: SubagentCommunication) => void)
    | undefined;
  let onLifecycle: ((snap: SubagentSnapshot) => void) | undefined;

  const reservePublicId = (id: string) => {
    const modelMatch = /^sa-(\d+)$/.exec(id);
    if (modelMatch) {
      const serial = Number(modelMatch[1]);
      if (Number.isSafeInteger(serial)) {
        modelCounter = Math.max(modelCounter, serial);
      }
      return;
    }
    const btwMatch = /^btw-(\d+)$/.exec(id);
    if (btwMatch) {
      const serial = Number(btwMatch[1]);
      if (Number.isSafeInteger(serial)) btwCounter = Math.max(btwCounter, serial);
    }
  };

  const notify = (id?: string) => {
    const waiters = changeWaiters;
    changeWaiters = [];
    for (const waiter of waiters) waiter();
    for (const listener of [...listeners]) {
      try {
        listener();
      } catch {
        // A failed status/render listener must not corrupt lifecycle state.
      }
    }
    if (id) {
      for (const listener of idListeners.get(id) ?? []) {
        try {
          listener();
        } catch {
          // Same.
        }
      }
    }
  };

  /** Resolves on the next state change. Interruption unregisters the waiter. */
  const nextChange = Effect.callback<void>((resume) => {
    const waiter = () => resume(Effect.void);
    changeWaiters.push(waiter);
    return Effect.sync(() => {
      const index = changeWaiters.indexOf(waiter);
      if (index >= 0) changeWaiters.splice(index, 1);
    });
  });

  const notifyLifecycle = (snapshot: SubagentSnapshot): boolean => {
    if (disposed || !onLifecycle) return true;
    try {
      onLifecycle(snapshot);
      return true;
    } catch {
      // Later checkpoints are best-effort; the initial start gate checks this
      // return value and refuses to launch work without a durable parent link.
      return false;
    }
  };

  const runningCount = () =>
    [...entries.values()].filter(
      (e) => e.snapshot.status === "running" || e.restarting === true,
    ).length;

  const addSuppression = (keys: ReadonlyArray<string>) => {
    for (const key of keys) {
      suppressedCompletions.set(
        key,
        (suppressedCompletions.get(key) ?? 0) + 1,
      );
    }
  };
  const releaseSuppression = (keys: ReadonlyArray<string>) => {
    for (const key of keys) {
      const count = (suppressedCompletions.get(key) ?? 1) - 1;
      if (count <= 0) suppressedCompletions.delete(key);
      else suppressedCompletions.set(key, count);
    }
  };
  const hasSuppressionForAgent = (id: string) =>
    [...suppressedCompletions.keys()].some((key) =>
      key.startsWith(`${id}:run-`),
    );

  const closeEntryScope = (entry: Entry) =>
    Scope.close(entry.scope, Exit.void).pipe(Effect.ignore);

  const pruneSettled = () => {
    if (entries.size <= MAX_TRACKED) return;
    const candidates = [...entries.values()]
      .filter(
        (e) =>
          e.snapshot.status !== "running" &&
          !hasSuppressionForAgent(e.snapshot.id),
      )
      .sort(
        (a, b) =>
          (a.snapshot.settledAt ?? a.snapshot.createdAt) -
          (b.snapshot.settledAt ?? b.snapshot.createdAt),
      );
    for (const entry of candidates) {
      if (entries.size <= MAX_TRACKED) break;
      entries.delete(entry.snapshot.id);
      const fiber = runDetached(closeEntryScope(entry));
      cleanups.add(fiber);
      fiber.addObserver(() => cleanups.delete(fiber));
    }
  };

  const settle = (entry: Entry, outcome: RunOutcome) => {
    const s = entry.snapshot;
    entry.restarting = false;
    if (s.status !== "running") return;
    s.settledAt = Date.now();
    switch (outcome._tag) {
      case "Completed":
        s.status = "done";
        s.errorText = undefined;
        s.finalText = outcome.finalText.slice(0, FINAL_TEXT_MAX_LENGTH);
        break;
      case "Failed":
        s.status = "error";
        s.errorText = bounded(outcome.errorText);
        // Never let a failed run report the previous run's successful output.
        s.finalText = (outcome.partialText ?? "").slice(
          0,
          FINAL_TEXT_MAX_LENGTH,
        );
        break;
      case "Interrupted":
        s.status = "error";
        s.errorText = "Run was aborted";
        s.finalText = (outcome.partialText ?? "").slice(
          0,
          FINAL_TEXT_MAX_LENGTH,
        );
        break;
    }
    s.liveAssistant = undefined;
    entry.liveToolMap.clear();
    s.liveTools = [];
    s.queued = [];
    const suppressed =
      (suppressedCompletions.get(subagentCompletionId(s)) ?? 0) > 0;
    notify(s.id);
    notifyLifecycle(s);
    try {
      // During teardown, don't queue results into a shutting-down session.
      if (!disposed) onSettled?.(s, suppressed);
    } catch {
      // The parent session may be unavailable; settlement stays final.
    }
    if (entry.restartCheckpointErrorRun === s.run) {
      releaseSuppression([subagentCompletionId(s)]);
    }
    pruneSettled();
  };

  const foldEvent = (entry: Entry, event: SubagentEvent) => {
    const s = entry.snapshot;
    switch (event._tag) {
      case "RunStarted": {
        entry.restarting = false;
        const lifecycleChanged = s.status !== "running";
        if (lifecycleChanged) s.run++;
        s.status = "running";
        s.settledAt = undefined;
        s.errorText = undefined;
        if (lifecycleChanged) {
          if (notifyLifecycle(s)) {
            entry.restartCheckpointErrorRun = undefined;
          } else {
            const failedRun = s.run;
            entry.restartCheckpointErrorRun = failedRun;
            addSuppression([subagentCompletionId(s)]);
            // The requester may be interrupted before it observes this event.
            // Make fail-closed abort ownership manager-local rather than
            // depending on the subagent_send tool effect staying alive.
            queueMicrotask(() => {
              if (
                entry.snapshot.run !== failedRun ||
                entry.restartCheckpointErrorRun !== failedRun
              ) {
                return;
              }
              const fiber = runDetached(
                abortEntry(entry).pipe(Effect.ignore),
              );
              cleanups.add(fiber);
              fiber.addObserver(() => cleanups.delete(fiber));
            });
          }
        }
        break;
      }
      case "RunSettled":
        settle(entry, event.outcome);
        return; // settle() already notified
      case "UserMessage":
        if (event.source === "teamlead") {
          const message: SubagentCommunication = {
            messageId: `lead-msg-${++teamleadMessageCounter}`,
            kind: "guidance",
            text: boundedTranscriptText(event.text),
            createdAt: Date.now(),
          };
          s.communications.push(message);
          appendTranscript(s, { kind: "communication", message });
          if (s.communications.length > MAX_COMMUNICATION_ITEMS) {
            s.communications.splice(
              0,
              s.communications.length - MAX_COMMUNICATION_ITEMS,
            );
          }
        } else {
          appendTranscript(s, {
            kind: "user",
            text: boundedTranscriptText(event.text),
          });
        }
        break;
      case "AssistantDelta": {
        const live = s.liveAssistant ?? { text: "", thinking: "" };
        s.liveAssistant =
          event.kind === "text"
            ? {
                ...live,
                text: (live.text + event.delta).slice(
                  -LIVE_ASSISTANT_MAX_LENGTH,
                ),
              }
            : {
                ...live,
                thinking: (live.thinking + event.delta).slice(
                  -LIVE_ASSISTANT_MAX_LENGTH,
                ),
              };
        break;
      }
      case "AssistantMessage":
        appendTranscript(s, {
          kind: "assistant",
          parts: event.parts.map((part) =>
            part.type === "toolCall"
              ? {
                  ...part,
                  argsPreview: part.argsPreview
                    ? boundedTranscriptText(part.argsPreview)
                    : undefined,
                }
              : { ...part, text: boundedTranscriptText(part.text) },
          ),
        });
        s.liveAssistant = undefined;
        s.turns++;
        break;
      case "ToolStart":
        entry.liveToolMap.set(event.toolId, {
          toolId: event.toolId,
          name: event.name,
          argsPreview: event.argsPreview
            ? boundedTranscriptText(event.argsPreview)
            : undefined,
        });
        s.liveTools = [...entry.liveToolMap.values()];
        break;
      case "ToolUpdate": {
        const current = entry.liveToolMap.get(event.toolId);
        if (current) {
          entry.liveToolMap.set(event.toolId, {
            ...current,
            outputPreview: event.outputPreview
              ? boundedTranscriptText(event.outputPreview)
              : current.outputPreview,
          });
          s.liveTools = [...entry.liveToolMap.values()];
        }
        break;
      }
      case "ToolEnd":
        entry.liveToolMap.delete(event.toolId);
        s.liveTools = [...entry.liveToolMap.values()];
        appendTranscript(s, {
          kind: "toolResult",
          toolId: event.toolId,
          name: event.name,
          isError: event.isError,
          outputPreview: event.outputPreview
            ? boundedTranscriptText(event.outputPreview)
            : undefined,
        });
        break;
      case "QueueChanged":
        s.queued = event.queued;
        if (s.status === "running") notifyLifecycle(s);
        break;
      case "MessageToLead": {
        const message: SubagentCommunication = {
          ...event.message,
          text: boundedTranscriptText(event.message.text),
        };
        s.communications.push(message);
        appendTranscript(s, { kind: "communication", message });
        if (s.communications.length > MAX_COMMUNICATION_ITEMS) {
          s.communications.splice(
            0,
            s.communications.length - MAX_COMMUNICATION_ITEMS,
          );
        }
        if (message.kind === "question" && message.requestId) {
          s.pendingQuestions = [
            ...s.pendingQuestions.filter(
              (question) => question.requestId !== message.requestId,
            ),
            {
              requestId: message.requestId,
              messageId: message.messageId,
              question: message.text,
              createdAt: message.createdAt,
            },
          ];
        }
        try {
          if (!disposed) onMessage?.(s, message);
        } catch {
          // Parent delivery failure must not corrupt child state.
        }
        break;
      }
      case "QuestionClosed": {
        s.pendingQuestions = s.pendingQuestions.filter(
          (question) => question.requestId !== event.requestId,
        );
        const communication: SubagentCommunication | undefined =
          event.outcome === "replied" && event.reply
            ? {
                messageId: event.messageId,
                requestId: event.requestId,
                kind: "reply",
                text: boundedTranscriptText(event.reply),
                createdAt: event.createdAt,
              }
            : event.outcome !== "replied"
              ? {
                  messageId: event.messageId,
                  requestId: event.requestId,
                  kind: "resolution",
                  text: `Question ${event.requestId} was ${event.outcome}.`,
                  createdAt: event.createdAt,
                }
              : undefined;
        if (communication) {
          s.communications.push(communication);
          appendTranscript(s, {
            kind: "communication",
            message: communication,
          });
          if (s.communications.length > MAX_COMMUNICATION_ITEMS) {
            s.communications.splice(
              0,
              s.communications.length - MAX_COMMUNICATION_ITEMS,
            );
          }
          if (communication.kind === "resolution") {
            try {
              if (!disposed) onMessage?.(s, communication);
            } catch {
              // Parent delivery failure must not corrupt child state.
            }
          }
        }
        break;
      }
      case "UsageChanged":
        s.usage = {
          tokens: event.tokens ?? s.usage.tokens,
          contextWindow: event.contextWindow ?? s.usage.contextWindow,
        };
        break;
      case "MetaChanged":
        s.meta = { ...s.meta, ...event.meta };
        break;
      case "BackendError":
        s.errorText = bounded(event.message);
        break;
    }
    notify(s.id);
  };

  const spawn = (backendName: BackendName, task: SpawnTask) =>
    Effect.gen(function* () {
      // Reserve synchronously (before the first yield inside doSpawn) so
      // parallel tool calls cannot race past the global cap.
      yield* Effect.suspend(
        (): Effect.Effect<void, SpawnError | ConcurrencyLimitError> => {
          if (disposed) {
            return new SpawnError({
              message: "Subagent manager is shutting down.",
            });
          }
          if (task.resume && entries.has(task.resume.id)) {
            return new SpawnError({
              message: `Subagent "${task.resume.id}" is already tracked.`,
            });
          }
          if (runningCount() + reserved >= MAX_RUNNING) {
            return new ConcurrencyLimitError({
              message: `Max ${MAX_RUNNING} subagents can run concurrently. Wait for one to finish before spawning another.`,
            });
          }
          reserved++;
          return Effect.void;
        },
      );

      const doSpawn = Effect.gen(function* () {
        const backend: SubagentBackend | undefined = registry.get(backendName);
        if (!backend) {
          return yield* new BackendUnavailableError({
            message: `Unknown backend "${backendName}".`,
          });
        }
        const available = yield* backend.available;
        if (!available) {
          return yield* new BackendUnavailableError({
            message: `Backend "${backendName}" is not available on this machine (binary/SDK/credentials missing).`,
          });
        }

        const scope = yield* Scope.make();
        const session = yield* Scope.provide(backend.spawn(task), scope).pipe(
          Effect.onError(() => Scope.close(scope, Exit.void)),
        );
        if (disposed) {
          yield* Scope.close(scope, Exit.void);
          return yield* new SpawnError({
            message: "Subagent manager shut down while spawning.",
          });
        }

        const origin = task.origin ?? "model";
        const id =
          task.resume?.id ??
          (origin === "btw" ? `btw-${++btwCounter}` : `sa-${++modelCounter}`);
        reservePublicId(id);
        const meta = yield* session.meta;
        const entry: Entry = {
          snapshot: {
            id,
            origin,
            backend: backendName,
            title: task.title,
            prompt: task.prompt,
            cwd: task.cwd,
            allowedSubagentsDepth: task.allowedSubagentsDepth ?? 0,
            status: "running",
            run: task.resume?.run ?? 1,
            createdAt: task.resume?.createdAt ?? Date.now(),
            meta,
            usage: { contextWindow: meta.contextWindow },
            transcript: [],
            liveTools: [],
            queued: [],
            communications: [],
            pendingQuestions: [],
            finalText: "",
            turns: 0,
          },
          session,
          scope,
          liveToolMap: new Map(),
        };
        entries.set(id, entry);
        notify(id);
        if (!notifyLifecycle(entry.snapshot)) {
          entries.delete(id);
          yield* Scope.close(scope, Exit.void).pipe(Effect.ignore);
          return yield* new SpawnError({
            message: `Could not persist the recovery checkpoint for "${id}"; subagent work was not started.`,
          });
        }

        // Pump: fold the event stream into the snapshot. Tied to the entry
        // scope, so closing the scope stops it. If the stream ends while the
        // subagent still looks running, the backend died out from under us.
        const pump = Stream.runForEach(session.events, (event) =>
          Effect.sync(() => foldEvent(entry, event)),
        ).pipe(
          Effect.ensuring(
            Effect.sync(() => {
              if (entry.snapshot.status === "running") {
                settle(entry, {
                  _tag: "Failed",
                  errorText: "Backend event stream ended unexpectedly",
                });
              }
            }),
          ),
        );
        entry.pump = yield* Scope.provide(Effect.forkScoped(pump), scope);

        // Pi uses this gate so no model/tool/extension-start work begins before
        // the durable parent manifest links the public id to its child session.
        if (session.start) {
          let startCompleted = false;
          let startError: string | undefined;
          yield* session.start.pipe(
            Effect.tap(() =>
              Effect.sync(() => {
                startCompleted = true;
              }),
            ),
            Effect.tapError((error) =>
              Effect.sync(() => {
                startError = error.message;
              }),
            ),
            Effect.ensuring(
              Effect.suspend(() => {
                if (startCompleted) return Effect.void;
                return Effect.gen(function* () {
                  const completionId = subagentCompletionId(entry.snapshot);
                  addSuppression([completionId]);
                  settle(entry, {
                    _tag: "Failed",
                    errorText: startError
                      ? `Could not start subagent: ${startError}`
                      : "Subagent start was interrupted",
                  });
                  releaseSuppression([completionId]);
                  entries.delete(id);
                  notify(id);
                  yield* Scope.close(scope, Exit.void).pipe(Effect.ignore);
                });
              }),
            ),
          );
        }
        return entry.snapshot as SubagentSnapshot;
      });

      return yield* doSpawn.pipe(
        Effect.ensuring(
          Effect.sync(() => {
            reserved--;
            notify();
          }),
        ),
      );
    });

  /** Interrupt one running entry, force-closing its scope after 5s. */
  const abortEntry = (entry: Entry) =>
    Effect.gen(function* () {
      if (entry.snapshot.status !== "running") return;
      const graceful = yield* entry.session.interrupt.pipe(
        Effect.timeout(STOP_TIMEOUT_MS),
        Effect.result,
      );
      if (Result.isFailure(graceful)) {
        // Settle before closing the scope so the pump's stream-ended
        // fallback ("Backend event stream ended unexpectedly") cannot win
        // the race and report the wrong terminal reason.
        yield* Effect.sync(() => {
          settle(entry, { _tag: "Interrupted" });
          entry.snapshot.errorText =
            "Abort deadline exceeded; session was force-disposed";
          notify(entry.snapshot.id);
        });
        // Bound the close like disposeAll does: a stuck backend finalizer
        // must not hang cancel after the run is already settled.
        yield* closeEntryScope(entry).pipe(
          Effect.timeout(STOP_TIMEOUT_MS),
          Effect.ignore,
        );
      }
    });

  const cancel = (ids: ReadonlyArray<string>) =>
    Effect.suspend(() => {
      const unique = [...new Set(ids)];
      const running = unique
        .map((id) => entries.get(id))
        .filter(
          (entry): entry is Entry => entry?.snapshot.status === "running",
        );
      const targets = running.map((entry) => ({
        entry,
        id: entry.snapshot.id,
        run: entry.snapshot.run,
      }));
      const runningIds = targets.map((target) => target.id);
      // Suppress only the exact runs canceled by this tool. A rapid restart
      // must not inherit suppression from the previous run.
      const suppressionKeys = targets.map(subagentCompletionId);
      addSuppression(suppressionKeys);
      const work = Effect.gen(function* () {
        yield* Effect.forEach(targets, ({ entry }) => abortEntry(entry), {
          concurrency: "unbounded",
        });
        while (
          targets.some(
            ({ entry, run }) =>
              entry.snapshot.run === run &&
              entry.snapshot.status === "running",
          )
        ) {
          yield* nextChange;
        }
      });
      return work.pipe(
        Effect.ensuring(
          Effect.sync(() => {
            releaseSuppression(suppressionKeys);
            pruneSettled();
          }),
        ),
        Effect.map((): ReadonlyArray<CancelResult> =>
          unique.map((id) => {
            const snapshot = entries.get(id)?.snapshot;
            const target = targets.find((candidate) => candidate.id === id);
            return {
              id,
              title: snapshot?.title ?? "?",
              status:
                target && snapshot?.run !== target.run
                  ? "error"
                  : (snapshot?.status ?? "error"),
              cancelled: runningIds.includes(id),
              completionId: target
                ? subagentCompletionId({ id, run: target.run })
                : undefined,
            };
          }),
        ),
      );
    });

  const sendWithSource = (
    id: string,
    text: string,
    source: SubagentInputSource,
  ) =>
    Effect.suspend((): Effect.Effect<MessageAcceptance, SendError> => {
      try {
        validateCommunicationText(text);
      } catch (error) {
        return new SendError({
          message: error instanceof Error ? error.message : String(error),
        });
      }
      const entry = entries.get(id);
      if (!entry || disposed) {
        return new SendError({
          message: `Subagent "${id}" is no longer tracked.`,
        });
      }
      // Restarting a settled subagent occupies a running slot again, so it
      // must respect the same cap as spawn. Steering an already-running one
      // does not consume additional capacity.
      if (entry.snapshot.status !== "running") {
        const statusAtAcceptance = entry.snapshot.status;
        const runAtAcceptance = entry.snapshot.run + 1;
        const acceptance: MessageAcceptance = {
          startsNewRun: true,
          completionId: subagentCompletionId({
            id: entry.snapshot.id,
            run: runAtAcceptance,
          }),
          statusAtAcceptance,
          runAtAcceptance,
        };
        // Another send has already reserved/restarted this settled session but
        // RunStarted has not reached the manager yet. Route subsequent sends
        // into that same backend start instead of charging another slot or
        // launching a second prompt.
        const sendAndAwaitCheckpoint = Effect.gen(function* () {
          yield* entry.session.send(text, source);
          // Do not expose the R+1 receipt/tool result before foldEvent has
          // advanced the run and synchronously persisted its lifecycle link.
          while (entry.snapshot.run < runAtAcceptance) {
            yield* nextChange;
          }
          if (entry.restartCheckpointErrorRun === runAtAcceptance) {
            yield* abortEntry(entry).pipe(Effect.ignore);
            return yield* new SendError({
              message: `Could not persist the recovery checkpoint for "${id}" run ${runAtAcceptance}; the restart was aborted.`,
            });
          }
          return acceptance;
        });
        if (entry.restarting) return sendAndAwaitCheckpoint;
        if (runningCount() + reserved >= MAX_RUNNING) {
          return new SendError({
            message: `Max ${MAX_RUNNING} subagents can run concurrently; restarting "${id}" would exceed that.`,
          });
        }
        // Occupy the slot synchronously: the RunStarted that flips status
        // arrives via the async pump, and two concurrent restarts must not
        // both pass the check in that window. Cleared by RunStarted/settle,
        // or here when the backend rejects the send.
        entry.restarting = true;
        return sendAndAwaitCheckpoint.pipe(
          Effect.onError(() =>
            Effect.sync(() => {
              entry.restarting = false;
            }),
          ),
        );
      }
      const acceptance: MessageAcceptance = {
        startsNewRun: false,
        statusAtAcceptance: entry.snapshot.status,
        runAtAcceptance: entry.snapshot.run,
      };
      return entry.session.send(text, source).pipe(Effect.as(acceptance));
    });

  const reply = (id: string, requestId: string, text: string) =>
    Effect.suspend((): Effect.Effect<void, ReplyError> => {
      try {
        validateCommunicationText(text);
      } catch (error) {
        return new ReplyError({
          message: error instanceof Error ? error.message : String(error),
        });
      }
      const entry = entries.get(id);
      if (!entry || disposed) {
        return new ReplyError({
          message: `Subagent "${id}" is no longer tracked.`,
        });
      }
      const pending = entry.snapshot.pendingQuestions.some(
        (question) => question.requestId === requestId,
      );
      if (!pending) {
        const known = entry.snapshot.pendingQuestions.map(
          (question) => question.requestId,
        );
        return new ReplyError({
          message: `Question "${requestId}" is not pending for ${id}. Pending: ${known.join(", ") || "none"}.`,
        });
      }
      return entry.session.reply(requestId, text);
    });

  const disposeAll = Effect.gen(function* () {
    disposed = true;
    const all = [...entries.values()];
    entries.clear();
    yield* Effect.forEach(
      all,
      (entry) =>
        closeEntryScope(entry).pipe(
          Effect.timeout(STOP_TIMEOUT_MS),
          Effect.ignore,
        ),
      { concurrency: "unbounded" },
    );
    // Pruning cleanups are detached; bound them like everything else so a
    // stuck backend finalizer cannot block runtime shutdown indefinitely.
    yield* Effect.forEach(
      [...cleanups],
      (fiber) =>
        Fiber.await(fiber).pipe(Effect.timeout(STOP_TIMEOUT_MS), Effect.ignore),
      { concurrency: "unbounded" },
    ).pipe(Effect.ignore);
    yield* Effect.sync(() => notify());
  });

  const view: SubagentReadModel = {
    list: () => [...entries.values()].map((entry) => entry.snapshot),
    get: (id) => entries.get(id)?.snapshot,
    size: () => entries.size,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    subscribeTo: (id, listener) => {
      let set = idListeners.get(id);
      if (!set) {
        set = new Set();
        idListeners.set(id, set);
      }
      set.add(listener);
      return () => {
        set.delete(listener);
        if (set.size === 0) idListeners.delete(id);
      };
    },
    requestSend: (id, text) => {
      runDetached(sendWithSource(id, text, "user").pipe(Effect.ignore));
    },
    requestAbort: (id) => {
      const entry = entries.get(id);
      if (!entry) return;
      // UI-initiated aborts are not suppressed: the failed result still
      // flows back to the parent as a follow-up message, matching v1.
      runDetached(abortEntry(entry).pipe(Effect.ignore));
    },
    setOnSettled: (hook) => {
      onSettled = hook;
    },
    setOnMessage: (hook) => {
      onMessage = hook;
    },
    setOnLifecycle: (hook) => {
      onLifecycle = hook;
    },
  };

  // Safety net: disposing the ManagedRuntime tears everything down even if
  // the extension forgot to call disposeAll explicitly.
  yield* Effect.addFinalizer(() => disposeAll);

  return SubagentManager.of({
    spawn,
    cancel,
    message: (id, text) => sendWithSource(id, text, "teamlead"),
    send: (id, text) =>
      sendWithSource(id, text, "user").pipe(Effect.asVoid),
    reply,
    get: (id) => Effect.sync(() => entries.get(id)?.snapshot),
    list: Effect.sync(() => [...entries.values()].map((e) => e.snapshot)),
    reserveIds: (ids) =>
      Effect.sync(() => {
        for (const id of ids) reservePublicId(id);
      }),
    disposeAll,
    view,
  });
});

export const SubagentManagerLive: Layer.Layer<
  SubagentManager,
  never,
  BackendRegistry
> = Layer.effect(SubagentManager, makeManager);
