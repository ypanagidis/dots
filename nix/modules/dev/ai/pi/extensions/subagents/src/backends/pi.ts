/**
 * pi backend — real implementation over the pi SDK.
 *
 * Each subagent is an in-process `AgentSession` (a port of v1
 * subagents/manager.ts + shared/child-session.ts):
 * - real session files visible in /resume, child resources loaded per-cwd
 *   with trust gating, and the child tool denylist;
 * - `session.subscribe()` events translated to normalized SubagentEvents;
 * - send() steers a streaming run or starts a fresh prompt() when idle;
 * - interrupt clears the queue and aborts; closing the session scope emits
 *   the child session_shutdown hook and disposes the session.
 */

import { randomUUID } from "node:crypto";
import type {
  AssistantMessage,
  Message,
  Model,
  ToolResultMessage,
} from "@earendil-works/pi-ai";
import type {
  AgentSession,
  AgentSessionEvent,
  ModelRegistry,
} from "@earendil-works/pi-coding-agent";
import {
  createAgentSession,
  DefaultResourceLoader,
  defineTool,
  getAgentDir,
  SessionManager,
  SettingsManager,
} from "@earendil-works/pi-coding-agent";
import type { Cause, Scope } from "effect";
import { Effect, Queue, Stream } from "effect";
import { Type } from "typebox";
import type { SubagentBackend, SubagentSession } from "../backend.ts";
import { BackgroundActivityTracker } from "../background-activity.ts";
import type {
  SpawnTask,
  SubagentEvent,
  SubagentInputSource,
  SubagentMeta,
  TranscriptPart,
} from "../domain.ts";
import {
  createCommunicationIdFactory,
  createPendingQuestionRegistry,
  createUpdateCommunication,
  validateCommunicationText,
} from "../communication.ts";
import { ReplyError, SendError, SpawnError } from "../domain.ts";
import {
  buildSubagentRecoveryPrompt,
  pendingRecoveryCompletionIdsFromEntries,
} from "../recovery.ts";
import {
  SUBAGENT_CHILD_LIFECYCLE_GUIDANCE,
  TEAMLEAD_ASK_PARAMETER_DESCRIPTIONS,
  TEAMLEAD_ASK_TOOL_DESCRIPTION,
  TEAMLEAD_SEND_PARAMETER_DESCRIPTIONS,
  TEAMLEAD_SEND_TOOL_DESCRIPTION,
} from "../prompt.ts";
import { createToolCallTimeoutGuard } from "../tool-call-timeout.ts";
import {
  createSubagentTreeBridge,
} from "../subagent-tree.ts";
import {
  createSubagentDepthPolicy,
  resolveSubagentSessionDepth,
  subagentDepthLimitFromEntries,
  SUBAGENT_DEPTH_POLICY_ENTRY_TYPE,
} from "../subagent-depth.ts";

const CHILD_SHUTDOWN_TIMEOUT_MS = 5_000;
const TEAMLEAD_REPLY_TIMEOUT_MS = 10 * 60 * 1_000;
const TEAMLEAD_GUIDANCE_MESSAGE_TYPE = "subagent-teamlead-guidance";

const CHILD_SUBAGENT_TOOL_NAMES = [
  "subagent_spawn",
  "subagent_wait",
  "subagent_cancel",
  "subagent_check",
  "subagent_list",
  "subagent_send",
  "subagent_reply",
] as const;

/** User-facing workflow and prompt tools stay unavailable in every headless child. */
const CHILD_ALWAYS_EXCLUDED_TOOL_NAMES = [
  "workflow",
  "ask_user",
  "ask_user_question",
] as const;

/** A positive allowance enables managed orchestration; zero keeps legacy behavior. */
export function childExcludedToolNames(
  allowedSubagentsDepth: number,
): ReadonlyArray<string> {
  return allowedSubagentsDepth > 0
    ? [...CHILD_ALWAYS_EXCLUDED_TOOL_NAMES]
    : [
        ...CHILD_SUBAGENT_TOOL_NAMES,
        ...CHILD_ALWAYS_EXCLUDED_TOOL_NAMES,
      ];
}

// --- Model + effort resolution -----------------------------------------------

type ThinkingLevel = NonNullable<
  NonNullable<Parameters<typeof createAgentSession>[0]>["thinkingLevel"]
>;

/**
 * Resolve the generic model hint against the parent registry (v1 semantics):
 * "provider/model-id" is exact; a bare id prefers the inherited provider,
 * then must be unambiguous across providers. No hint inherits the parent
 * model; with nothing to inherit, the SDK default applies.
 */
function resolvePiModel(
  registry: ModelRegistry,
  hint: string | undefined,
  inherited: { provider: string; id: string } | undefined,
): Model<any> | undefined {
  if (!hint) {
    if (!inherited) return undefined;
    return registry.find(inherited.provider, inherited.id) ?? undefined;
  }
  const slash = hint.indexOf("/");
  if (slash > 0) {
    const provider = hint.slice(0, slash);
    const id = hint.slice(slash + 1);
    const found = registry.find(provider, id);
    if (found) return found;
    throw new Error(`Unknown model "${hint}".`);
  }
  if (inherited) {
    const found = registry.find(inherited.provider, hint);
    if (found) return found;
  }
  const matches = registry.getAll().filter((m) => m.id === hint);
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) {
    throw new Error(
      `Model "${hint}" exists in multiple providers (${matches.map((m) => m.provider).join(", ")}). Use "provider/${hint}".`,
    );
  }
  throw new Error(`Unknown model "${hint}".`);
}

// --- Child session helpers (ported from v1 shared/child-session.ts) -----------

/** Load normal global/package resources and trust-gated project resources. */
async function createChildResources(
  cwd: string,
  projectTrusted: boolean,
  allowedSubagentsDepth: number,
  treeRegistry: SpawnTask["parent"]["treeRegistry"],
) {
  const agentDir = getAgentDir();
  const settingsManager = SettingsManager.create(cwd, agentDir, {
    projectTrusted,
  });
  const loader = new DefaultResourceLoader({
    cwd,
    agentDir,
    settingsManager,
    extensionFactories:
      treeRegistry && allowedSubagentsDepth > 0
        ? [createSubagentTreeBridge(treeRegistry)]
        : [],
    appendSystemPromptOverride: (base) => [
      ...base,
      SUBAGENT_CHILD_LIFECYCLE_GUIDANCE,
      allowedSubagentsDepth > 0
        ? `[Subagent delegation]\nThis session may create managed descendants. Its remaining descendant-depth allowance is ${allowedSubagentsDepth}. Every subagent_spawn call must set allowed_subagents_depth to at most ${allowedSubagentsDepth - 1}; omitted means 0.\n[/Subagent delegation]`
        : "[Subagent delegation]\nThis session may not create managed descendants.\n[/Subagent delegation]",
    ],
  });
  await loader.reload();
  return { loader, settingsManager };
}

function waitBounded(operation: Promise<unknown>, timeoutMs: number) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<void>((resolve) => {
    timer = setTimeout(resolve, timeoutMs);
  });
  return Promise.race([
    operation.then(
      () => undefined,
      () => undefined,
    ),
    timeout,
  ])
    .catch(() => {})
    .finally(() => {
      if (timer) clearTimeout(timer);
    });
}

function interruptedToolResult(
  toolCallId: string,
  toolName: string,
): ToolResultMessage {
  return {
    role: "toolResult",
    toolCallId,
    toolName,
    content: [
      {
        type: "text",
        text: "This tool call was interrupted when the previous Pi process ended. Inspect current state before retrying it.",
      },
    ],
    isError: true,
    timestamp: Date.now(),
  };
}

/**
 * A hard crash can leave a finalized assistant tool call without its result.
 * Repair the in-memory sequence before adding the recovery user turn. Results
 * for a trailing interrupted batch are also appended durably; older malformed
 * spans are repaired in-memory at their original boundary.
 */
export function repairInterruptedToolCallMessages(
  messages: ReadonlyArray<(AgentSession["messages"])[number]>,
): {
  readonly messages: Array<(AgentSession["messages"])[number]>;
  readonly trailingSynthetic: ReadonlyArray<ToolResultMessage>;
  readonly syntheticCount: number;
} {
  const repaired: Array<(AgentSession["messages"])[number]> = [];
  const pending = new Map<string, string>();
  let trailingSynthetic: ToolResultMessage[] = [];
  let syntheticCount = 0;

  const flushPending = (trailing: boolean) => {
    if (pending.size === 0) return;
    const synthetic = [...pending].map(([id, name]) =>
      interruptedToolResult(id, name),
    );
    repaired.push(...synthetic);
    syntheticCount += synthetic.length;
    if (trailing) trailingSynthetic = synthetic;
    pending.clear();
  };

  for (const message of messages) {
    const role = messageRole(message);
    if (
      pending.size > 0 &&
      role !== "toolResult" &&
      role !== undefined
    ) {
      flushPending(false);
    }
    repaired.push(message);
    if (role === "assistant") {
      for (const part of (message as AssistantMessage).content) {
        if (part.type === "toolCall") pending.set(part.id, part.name);
      }
    } else if (role === "toolResult") {
      pending.delete((message as ToolResultMessage).toolCallId);
    }
  }
  flushPending(true);
  return { messages: repaired, trailingSynthetic, syntheticCount };
}

function repairInterruptedToolCalls(session: AgentSession): number {
  const repaired = repairInterruptedToolCallMessages(session.messages);
  for (const result of repaired.trailingSynthetic) {
    session.sessionManager.appendMessage(result);
  }
  if (repaired.syntheticCount > 0) {
    session.agent.state.messages = repaired.messages;
  }
  return repaired.syntheticCount;
}

export function recoveredSessionNeedsContinuation(options: {
  readonly tailRole: SessionMessageRole | undefined;
  readonly lastStopReason: AssistantMessage["stopReason"] | undefined;
  readonly interruptedToolCalls: number;
  readonly pendingBackgroundTasks: number;
  readonly queuedMessages: number;
}): boolean {
  return !(
    options.tailRole === "assistant" &&
    options.lastStopReason === "stop" &&
    options.interruptedToolCalls === 0 &&
    options.pendingBackgroundTasks === 0 &&
    options.queuedMessages === 0
  );
}

/** Emit child session_shutdown (bounded), then dispose. Never throws. */
async function shutdownAndDisposeChildSession(session: AgentSession) {
  try {
    if (session.extensionRunner.hasHandlers("session_shutdown")) {
      await waitBounded(
        session.extensionRunner.emit({
          type: "session_shutdown",
          reason: "quit",
        }),
        CHILD_SHUTDOWN_TIMEOUT_MS,
      );
    }
  } catch {
    // Extension runner inspection/emission is best-effort during teardown.
  } finally {
    try {
      session.dispose();
    } catch {
      // Disposal is terminal and must remain idempotent for callers.
    }
  }
}

// --- Event translation ----------------------------------------------------------

type SessionMessageRole = Message["role"] | "custom";

function messageRole(msg: unknown): SessionMessageRole | undefined {
  const role = (msg as { role?: string } | undefined)?.role;
  if (
    role === "user" ||
    role === "assistant" ||
    role === "toolResult" ||
    role === "custom"
  )
    return role;
  return undefined;
}

function lastAssistantMessage(
  session: AgentSession,
): AssistantMessage | undefined {
  const messages = session.messages;
  for (let i = messages.length - 1; i >= 0; i--) {
    const msg = messages[i];
    if (messageRole(msg) === "assistant") return msg as AssistantMessage;
  }
  return undefined;
}

/** Final assistant text output (last assistant message with text), v1 semantics. */
function finalOutput(session: AgentSession): string {
  const messages = session.messages;
  for (let i = messages.length - 1; i >= 0; i--) {
    const msg = messages[i];
    if (messageRole(msg) !== "assistant") continue;
    const text = (msg as AssistantMessage).content
      .filter((part) => part.type === "text")
      .map((part) => part.text)
      .join("\n")
      .trim();
    if (text) return text;
  }
  return "";
}

function safeJson(value: unknown): string | undefined {
  try {
    const text = JSON.stringify(value);
    return text === "{}" ? undefined : text.slice(0, 4_096);
  } catch {
    return undefined;
  }
}

/** First non-empty line of a tool result-ish value (v1 liveToolPreview). */
function toolPreview(value: unknown): string | undefined {
  if (typeof value === "string") {
    return value
      .split("\n")
      .find((line) => line.trim())
      ?.trim();
  }
  if (!value || typeof value !== "object") return undefined;
  const content = (value as { content?: unknown }).content;
  if (!Array.isArray(content)) return undefined;
  for (const part of content) {
    if (!part || typeof part !== "object") continue;
    const record = part as { type?: unknown; text?: unknown };
    if (record.type !== "text" || typeof record.text !== "string") continue;
    const firstLine = record.text.split("\n").find((line) => line.trim());
    if (firstLine) return firstLine.trim();
  }
  return undefined;
}

function assistantParts(msg: AssistantMessage): TranscriptPart[] {
  const parts: TranscriptPart[] = [];
  for (const part of msg.content) {
    if (part.type === "text") {
      parts.push({ type: "text", text: part.text });
    } else if (part.type === "thinking") {
      parts.push({
        type: "thinking",
        text: part.redacted ? "" : part.thinking,
        redacted: part.redacted,
      });
    } else if (part.type === "toolCall") {
      parts.push({
        type: "toolCall",
        toolId: part.id,
        name: part.name,
        argsPreview: safeJson(part.arguments),
      });
    }
  }
  return parts;
}

function userText(msg: unknown): string {
  const content = (msg as { content: unknown }).content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter(
      (part): part is { type: "text"; text: string } =>
        !!part &&
        typeof part === "object" &&
        (part as { type?: unknown }).type === "text",
    )
    .map((part) => part.text)
    .join("\n");
}

/** Translate only transcript-bearing user/teamlead messages. */
export function piTranscriptUserEvent(
  message: unknown,
): Extract<SubagentEvent, { _tag: "UserMessage" }> | undefined {
  const role = messageRole(message);
  const source =
    role === "user"
      ? "user"
      : role === "custom" &&
          (message as { customType?: string }).customType ===
            TEAMLEAD_GUIDANCE_MESSAGE_TYPE
        ? "teamlead"
        : undefined;
  if (!source) return undefined;
  const text = userText(message);
  if (!text.trim()) return undefined;
  return { _tag: "UserMessage", text, source };
}

// --- The session ------------------------------------------------------------------

function boundedError(error: unknown) {
  return (error instanceof Error ? error.message : String(error)).slice(
    0,
    4096,
  );
}

const makePiSession = (
  task: SpawnTask,
): Effect.Effect<SubagentSession, SpawnError, Scope.Scope> =>
  Effect.gen(function* () {
    const registry = task.parent.modelRegistry;
    if (!registry) {
      return yield* new SpawnError({
        message: "pi backend requires the parent session's model registry.",
      });
    }

    const model = yield* Effect.try({
      try: () =>
        resolvePiModel(registry, task.model, task.parent.inheritedModel),
      catch: (error) => new SpawnError({ message: boundedError(error) }),
    });
    // pi's thinking levels ARE the shared reasoning-effort scale.
    const thinkingLevel = (task.reasoningEffort ??
      task.parent.inheritedThinkingLevel) as ThinkingLevel | undefined;

    const state = {
      closed: false,
      /** prompt() rejection for the active run; folded into RunSettled. */
      runError: undefined as string | undefined,
      /** One terminal event per run: lifecycle, prompt-rejection, and abort
       * fallbacks can all race to settle; the first wins. */
      settled: false,
      /** prompt() accepted/start lifecycle has not reached agent_start yet. */
      starting: false,
      startCancelled: false,
      cancelling: false,
      queuedWhileStarting: [] as Array<{
        readonly text: string;
        readonly source: SubagentInputSource;
        readonly acceptance?: {
          readonly resolve: () => void;
          readonly reject: (error: Error) => void;
        };
      }>,
    };

    const backgroundActivity = new BackgroundActivityTracker();
    const pendingGuidanceAcceptances = new Map<
      string,
      { readonly resolve: () => void; readonly reject: (error: Error) => void }
    >();
    const toolInputs = new Map<
      string,
      { readonly toolName: string; readonly args: unknown }
    >();

    // The queue and communication bridge must exist before createAgentSession:
    // a very fast child can call teamlead_send/teamlead_ask immediately.
    const events = yield* Queue.make<SubagentEvent, Cause.Done>();
    const emit = (event: SubagentEvent) => {
      Queue.offerUnsafe(events, event);
    };
    const communicationIds = createCommunicationIdFactory();
    const pendingQuestions = createPendingQuestionRegistry({
      ids: communicationIds,
      timeoutMs: TEAMLEAD_REPLY_TIMEOUT_MS,
      onSettled: ({ requestId, state: outcome, reply }) => {
        emit({
          _tag: "QuestionClosed",
          requestId,
          messageId: reply?.messageId ?? communicationIds.nextMessageId(),
          outcome:
            outcome === "answered"
              ? "replied"
              : outcome === "timed-out"
                ? "timed-out"
                : "cancelled",
          reply: reply?.text,
          createdAt: reply?.createdAt ?? Date.now(),
        });
      },
    });

    const teamleadSendTool = defineTool({
      name: "teamlead_send",
      label: "Message Teamlead",
      description: TEAMLEAD_SEND_TOOL_DESCRIPTION,
      promptSnippet:
        "Send a material asynchronous update to the teamlead while continuing work",
      promptGuidelines: [
        "Use teamlead_send only for material findings, blockers, or coordination updates; continue useful work after sending and do not poll for a response.",
      ],
      parameters: Type.Object({
        message: Type.String({
          description: TEAMLEAD_SEND_PARAMETER_DESCRIPTIONS.message,
        }),
      }),
      async execute(_toolCallId, params) {
        if (state.closed) throw new Error("Subagent session is closed.");
        const message = createUpdateCommunication(
          params.message,
          communicationIds,
        );
        emit({ _tag: "MessageToLead", message });
        return {
          content: [
            {
              type: "text",
              text: `Update ${message.messageId} queued for the teamlead. Continue working; do not poll.`,
            },
          ],
          details: { messageId: message.messageId },
        };
      },
    });

    const teamleadAskTool = defineTool({
      name: "teamlead_ask",
      label: "Ask Teamlead",
      description: TEAMLEAD_ASK_TOOL_DESCRIPTION,
      promptSnippet:
        "Ask the teamlead a blocking, correlated question when a decision is required",
      promptGuidelines: [
        "Use teamlead_ask only when a teamlead decision is genuinely required; it waits for a targeted reply and must not be polled or repeated.",
      ],
      parameters: Type.Object({
        question: Type.String({
          description: TEAMLEAD_ASK_PARAMETER_DESCRIPTIONS.question,
        }),
      }),
      async execute(_toolCallId, params, signal) {
        if (state.closed) throw new Error("Subagent session is closed.");
        if (signal?.aborted) throw new Error("Teamlead question was aborted.");
        const pending = pendingQuestions.ask(params.question, { signal });
        emit({ _tag: "MessageToLead", message: pending.communication });
        const reply = await pending.result;
        const { requestId, messageId } = pending.communication;
        return {
          content: [
            {
              type: "text",
              text: `Teamlead reply to ${requestId}:\n\n${reply}`,
            },
          ],
          details: { requestId, messageId },
        };
      },
    });

    const customTools =
      (task.origin ?? "model") === "model"
        ? [teamleadSendTool, teamleadAskTool]
        : [];

    let repairedInterruptedToolCalls = 0;
    let extensionBindingStarted = false;
    const session = yield* Effect.tryPromise({
      try: async () => {
        const sessionManager = task.resume
          ? SessionManager.open(task.resume.sessionFilePath)
          : SessionManager.create(task.cwd);
        const persistedDepth = subagentDepthLimitFromEntries(
          sessionManager.getEntries(),
        );
        const allowedSubagentsDepth = resolveSubagentSessionDepth({
          requestedDepth: task.allowedSubagentsDepth ?? 0,
          persistedDepth,
          resuming: task.resume !== undefined,
        });
        if (!task.resume || persistedDepth === undefined) {
          sessionManager.appendCustomEntry(
            SUBAGENT_DEPTH_POLICY_ENTRY_TYPE,
            createSubagentDepthPolicy(allowedSubagentsDepth),
          );
        }
        const { loader, settingsManager } = await createChildResources(
          task.cwd,
          task.parent.projectTrusted,
          allowedSubagentsDepth,
          task.parent.treeRegistry,
        );
        const { session } = await createAgentSession({
          cwd: task.cwd,
          sessionManager,
          settingsManager,
          resourceLoader: loader,
          model,
          // A reopened session restores its own recorded thinking level.
          thinkingLevel: task.resume ? undefined : thinkingLevel,
          excludeTools: [...childExcludedToolNames(allowedSubagentsDepth)],
          customTools,
        });
        if (task.resume) {
          repairedInterruptedToolCalls = repairInterruptedToolCalls(session);
        }
        return session;
      },
      catch: (error) => new SpawnError({ message: boundedError(error) }),
    });

    const toolTimeout = createToolCallTimeoutGuard(undefined, {
      // teamlead_ask owns its longer request/reply timeout and cancellation.
      exclude: new Set(["teamlead_ask"]),
    });
    toolTimeout.apply(session);

    const activeModel = (): Model<any> | undefined => {
      const sessionModel = session.model;
      const last = lastAssistantMessage(session);
      if (!last) return sessionModel;
      if (
        sessionModel &&
        (last.provider !== sessionModel.provider ||
          last.model !== sessionModel.id)
      ) {
        // The session changed models after this assistant response.
        return sessionModel;
      }
      return (
        registry.find(last.provider, last.responseModel ?? last.model) ??
        sessionModel
      );
    };

    const currentMeta = (): SubagentMeta => {
      const m = activeModel();
      return {
        backend: "pi",
        modelLabel: m ? `${m.provider}/${m.id}` : undefined,
        contextWindow: m?.contextWindow,
        sessionFilePath: session.sessionFile,
        nativeSessionId: session.sessionId,
      };
    };

    const emitUsage = () => {
      const usage = session.getContextUsage();
      emit({
        _tag: "UsageChanged",
        tokens: usage?.tokens ?? undefined,
        contextWindow: activeModel()?.contextWindow ?? usage?.contextWindow,
      });
    };

    const settle = () => {
      if (state.settled) return;
      state.settled = true;
      const last = lastAssistantMessage(session);
      const partialText = finalOutput(session) || undefined;
      if (last?.stopReason === "aborted") {
        emit({
          _tag: "RunSettled",
          outcome: { _tag: "Interrupted", partialText },
        });
        return;
      }
      const errorText =
        state.runError ??
        (last?.stopReason === "error"
          ? (last.errorMessage ?? "Run failed")
          : undefined);
      if (errorText !== undefined) {
        emit({
          _tag: "RunSettled",
          outcome: {
            _tag: "Failed",
            errorText: boundedError(errorText),
            partialText,
          },
        });
        return;
      }
      emit({
        _tag: "RunSettled",
        outcome: { _tag: "Completed", finalText: finalOutput(session) },
      });
    };

    const sendGuidanceDuringRun = (
      text: string,
      acceptanceId?: string,
    ) =>
      session.sendCustomMessage(
        {
          customType: TEAMLEAD_GUIDANCE_MESSAGE_TYPE,
          content: text,
          display: true,
          details: {
            source: "teamlead",
            ...(acceptanceId ? { acceptanceId } : {}),
          },
        },
        { deliverAs: "steer", triggerTurn: true },
      );

    const sendGuidanceWithAcceptance = (text: string): Promise<void> => {
      const acceptanceId = `guidance-${randomUUID()}`;
      return new Promise<void>((resolve, reject) => {
        pendingGuidanceAcceptances.set(acceptanceId, { resolve, reject });
        void sendGuidanceDuringRun(text, acceptanceId).catch((error) => {
          const acceptance = pendingGuidanceAcceptances.get(acceptanceId);
          pendingGuidanceAcceptances.delete(acceptanceId);
          if (!acceptance) return;
          acceptance.reject(
            error instanceof Error ? error : new Error(String(error)),
          );
        });
      });
    };

    const flushQueuedWhileStarting = () => {
      const queued = state.queuedWhileStarting.splice(0);
      for (const message of queued) {
        const delivery =
          message.source === "teamlead"
            ? sendGuidanceWithAcceptance(message.text)
            : session.steer(message.text);
        void delivery.then(message.acceptance?.resolve).catch((error) => {
          message.acceptance?.reject(
            error instanceof Error ? error : new Error(String(error)),
          );
          if (!state.closed) {
            emit({ _tag: "BackendError", message: boundedError(error) });
          }
        });
      }
      emit({ _tag: "QueueChanged", queued: [] });
    };

    const handleEvent = (event: AgentSessionEvent) => {
      if (state.closed) return;
      switch (event.type) {
        case "agent_start":
          // Completion callbacks are injected as custom messages. Reconcile
          // from the durable message list as well as message_end so this does
          // not depend on a particular extension delivery event sequence.
          for (const message of session.messages) {
            backgroundActivity.recordCompleted(message);
          }
          // Extensions may register tools between runs; guard new ones too.
          toolTimeout.apply(session);
          state.starting = false;
          if (state.startCancelled) {
            // Cancellation won during prompt preflight. Do not resurrect the
            // manager run if the SDK starts anyway; abort this late lifecycle.
            void session.abort().catch(() => undefined);
            break;
          }
          state.settled = false;
          emit({ _tag: "RunStarted" });
          flushQueuedWhileStarting();
          break;
        case "message_update": {
          const streamEvent = event.assistantMessageEvent;
          if (streamEvent.type === "text_delta") {
            emit({
              _tag: "AssistantDelta",
              kind: "text",
              delta: streamEvent.delta,
            });
          } else if (streamEvent.type === "thinking_delta") {
            emit({
              _tag: "AssistantDelta",
              kind: "thinking",
              delta: streamEvent.delta,
            });
          }
          break;
        }
        case "message_end": {
          if (
            messageRole(event.message) === "custom" &&
            (event.message as { customType?: string }).customType ===
              TEAMLEAD_GUIDANCE_MESSAGE_TYPE
          ) {
            const acceptanceId = (
              event.message as { details?: { acceptanceId?: unknown } }
            ).details?.acceptanceId;
            if (typeof acceptanceId === "string") {
              // AgentSession notifies subscribers before persisting message_end.
              // Defer one microtask and verify the exact custom entry exists so
              // the acceptance receipt cannot outrun its durable guidance.
              queueMicrotask(() => {
                const acceptance =
                  pendingGuidanceAcceptances.get(acceptanceId);
                if (!acceptance) return;
                const durable = session.sessionManager.getEntries().some(
                  (entry) =>
                    entry.type === "custom_message" &&
                    entry.customType === TEAMLEAD_GUIDANCE_MESSAGE_TYPE &&
                    (
                      entry.details as
                        | { acceptanceId?: unknown }
                        | undefined
                    )?.acceptanceId === acceptanceId,
                );
                pendingGuidanceAcceptances.delete(acceptanceId);
                if (durable) {
                  acceptance.resolve();
                } else {
                  acceptance.reject(
                    new Error("Teamlead guidance was not persisted"),
                  );
                }
              });
            }
          }
          // Callback-enabled nested background tasks publish a custom completion
          // message before triggering their continuation turn. Clear the hold,
          // but let that continuation's agent_settled produce the one terminal
          // manager event for the whole logical run.
          backgroundActivity.recordCompleted(event.message);
          const role = messageRole(event.message);
          const userEvent = piTranscriptUserEvent(event.message);
          if (userEvent) {
            emit(userEvent);
          } else if (role === "assistant") {
            emit({
              _tag: "AssistantMessage",
              parts: assistantParts(event.message as AssistantMessage),
            });
            emitUsage();
            emit({ _tag: "MetaChanged", meta: currentMeta() });
          }
          // toolResult messages are covered by tool_execution_end.
          break;
        }
        case "tool_execution_start":
          toolInputs.set(event.toolCallId, {
            toolName: event.toolName,
            args: event.args,
          });
          emit({
            _tag: "ToolStart",
            toolId: event.toolCallId,
            name: event.toolName,
            argsPreview: safeJson(event.args),
          });
          break;
        case "tool_execution_update":
          emit({
            _tag: "ToolUpdate",
            toolId: event.toolCallId,
            outputPreview: toolPreview(event.partialResult),
          });
          break;
        case "tool_execution_end": {
          const input = toolInputs.get(event.toolCallId);
          toolInputs.delete(event.toolCallId);
          backgroundActivity.recordCompleted(event.result);
          backgroundActivity.recordStarted({
            toolName: input?.toolName ?? event.toolName,
            args: input?.args,
            result: event.result,
            isError: event.isError,
          });
          emit({
            _tag: "ToolEnd",
            toolId: event.toolCallId,
            name: event.toolName,
            isError: event.isError,
            outputPreview: toolPreview(event.result),
          });
          break;
        }
        case "entry_appended":
          // Nested coordinator checkpoints are the durable source of truth for
          // lifecycle holds, including the gap before a tool result is written.
          backgroundActivity.reconcilePendingSubagents(
            pendingRecoveryCompletionIdsFromEntries(
              session.sessionManager.getBranch(),
            ),
          );
          break;
        case "queue_update":
          emit({
            _tag: "QueueChanged",
            queued: [
              ...event.steering.map((text) => ({
                text,
                kind: "steer" as const,
              })),
              ...event.followUp.map((text) => ({
                text,
                kind: "follow-up" as const,
              })),
            ],
          });
          break;
        case "agent_settled":
          // A model turn may go idle while callback-enabled work continues.
          // Keep the manager run active so messages can start another turn and
          // the child remains visible/counts toward concurrency until the final
          // background callback continuation settles.
          if (backgroundActivity.pendingCount === 0) settle();
          break;
      }
    };
    const unsubscribe = session.subscribe(handleEvent);

    // Rebuild enough of the child transcript for takeover/history views. The
    // child JSONL remains authoritative; replayed events are in-memory only.
    if (task.resume) {
      const replayTools = new Map<
        string,
        { readonly name: string; readonly args: unknown }
      >();
      for (const message of session.messages) {
        const role = messageRole(message);
        backgroundActivity.recordCompleted(message);
        if (role === "user" || role === "custom") {
          const userEvent = piTranscriptUserEvent(message);
          if (userEvent) emit(userEvent);
          continue;
        }
        if (role === "assistant") {
          const assistant = message as AssistantMessage;
          for (const part of assistant.content) {
            if (part.type === "toolCall") {
              replayTools.set(part.id, {
                name: part.name,
                args: part.arguments,
              });
            }
          }
          emit({ _tag: "AssistantMessage", parts: assistantParts(assistant) });
          continue;
        }
        if (role === "toolResult") {
          const result = message as {
            toolCallId: string;
            toolName: string;
            isError: boolean;
            content: unknown;
          };
          const replayTool = replayTools.get(result.toolCallId);
          const toolName = result.toolName ?? replayTool?.name ?? "tool";
          backgroundActivity.recordStarted({
            toolName,
            args: replayTool?.args,
            result,
            isError: result.isError,
          });
          emit({
            _tag: "ToolEnd",
            toolId: result.toolCallId,
            name: toolName,
            isError: result.isError,
            outputPreview: toolPreview(result),
          });
        }
      }
      backgroundActivity.reconcilePendingSubagents(
        pendingRecoveryCompletionIdsFromEntries(
          session.sessionManager.getBranch(),
        ),
      );
      emitUsage();
    }
    const resumeAlreadyComplete =
      task.resume !== undefined &&
      !recoveredSessionNeedsContinuation({
        tailRole: messageRole(session.messages.at(-1)),
        lastStopReason: lastAssistantMessage(session)?.stopReason,
        interruptedToolCalls: repairedInterruptedToolCalls,
        pendingBackgroundTasks: backgroundActivity.pendingCount,
        queuedMessages: task.resume.queued?.length ?? 0,
      });

    yield* Effect.addFinalizer(() =>
      Effect.promise(async () => {
        state.closed = true;
        backgroundActivity.clear();
        toolInputs.clear();
        pendingQuestions.close("Subagent session shutdown");
        for (const queued of state.queuedWhileStarting.splice(0)) {
          queued.acceptance?.reject(new Error("Subagent session shutdown"));
        }
        for (const acceptance of pendingGuidanceAcceptances.values()) {
          acceptance.reject(new Error("Subagent session shutdown"));
        }
        pendingGuidanceAcceptances.clear();
        unsubscribe();
        try {
          session.clearQueue();
        } catch {
          // Continue with abort/dispose.
        }
        await waitBounded(session.abort(), CHILD_SHUTDOWN_TIMEOUT_MS);
        if (extensionBindingStarted) {
          await shutdownAndDisposeChildSession(session);
        } else {
          try {
            session.dispose();
          } catch {
            // The unbound session still needs best-effort terminal cleanup.
          }
        }
        Queue.endUnsafe(events);
      }),
    );

    /**
     * Start one fresh run and resolve once Pi accepts prompt preflight. While
     * preflight is open, send() queues into this run instead of starting a
     * second concurrent prompt.
     */
    function startQueuedRun(message: {
      readonly text: string;
      readonly source: SubagentInputSource;
    }) {
      if (message.source === "teamlead") {
        void startGuidanceRun(message.text).catch(() => undefined);
      } else {
        void startRun(message.text).catch(() => undefined);
      }
    }

    function startGuidanceRun(text: string): Promise<void> {
      state.runError = undefined;
      state.settled = false;
      state.starting = true;
      state.startCancelled = false;
      emit({ _tag: "RunStarted" });
      return sendGuidanceWithAcceptance(text).catch((error) => {
        state.starting = false;
        state.runError = boundedError(error);
        if (!session.isStreaming) settle();
        throw error;
      });
    }

    function startRun(text: string): Promise<void> {
      state.runError = undefined;
      state.settled = false;
      state.starting = true;
      state.startCancelled = false;
      emit({ _tag: "RunStarted" });

      return new Promise<void>((resolve, reject) => {
        let preflightFinished = false;
        void session
          .prompt(text, {
            source: "extension",
            preflightResult: (accepted) => {
              if (preflightFinished) return;
              preflightFinished = true;
              if (accepted) {
                resolve();
                return;
              }
              state.starting = false;
              const error = new Error("Subagent prompt was rejected during preflight.");
              state.runError = error.message;
              settle();
              reject(error);
              const next = state.queuedWhileStarting.shift();
              if (next !== undefined && !state.startCancelled && !state.closed) {
                queueMicrotask(() => startQueuedRun(next));
              }
            },
          })
          .catch((error) => {
            state.runError = boundedError(error);
            if (!preflightFinished) {
              preflightFinished = true;
              state.starting = false;
              reject(error);
            }
            // Preflight failures may never start the agent lifecycle, so no
            // agent_settled will arrive for them.
            if (!session.isStreaming) settle();
          });
      });
    }

    // Session naming is best-effort and already exists on a reopened child.
    if (!task.resume) {
      yield* Effect.try(() =>
        session.sessionManager.appendSessionInfo(
          `${task.origin === "btw" ? "btw" : "subagent"}: ${task.title}`,
        ),
      ).pipe(Effect.ignore);
    }

    emit({ _tag: "MetaChanged", meta: currentMeta() });

    return {
      meta: Effect.sync(currentMeta),
      events: Stream.fromQueue(events),
      start: Effect.tryPromise({
        try: async () => {
          // Bind session hooks only after the manager has durably checkpointed
          // this child and installed its event pump. A nested coordinator's
          // session_start may recover descendants immediately.
          extensionBindingStarted = true;
          await session.bindExtensions({ mode: "print" });
          // Effect interruption cannot abort arbitrary extension promises. The
          // manager closes this scope on an interrupted start gate; never let
          // a late bind completion resurrect model work afterward.
          if (state.closed) return;
          if (resumeAlreadyComplete) {
            // The child reached a durable final assistant response; only the
            // parent terminal checkpoint/callback was lost in the crash window.
            settle();
            return;
          }
          void startRun(
            task.resume
              ? buildSubagentRecoveryPrompt(task.prompt, task.resume.queued)
              : task.prompt,
          ).catch(() => undefined);
        },
        catch: (error) => new SpawnError({ message: boundedError(error) }),
      }),
      send: (text, source) =>
        Effect.suspend((): Effect.Effect<void, SendError> => {
          if (state.closed) {
            return new SendError({ message: "Subagent session is closed." });
          }
          if (state.cancelling) {
            return new SendError({
              message:
                "Subagent cancellation is still in progress; retry after it settles.",
            });
          }
          if (
            state.startCancelled &&
            (state.starting || session.isStreaming)
          ) {
            return new SendError({
              message:
                "Subagent cancellation is still in progress; retry after it settles.",
            });
          }
          if (state.starting) {
            if (source === "teamlead") {
              return Effect.tryPromise({
                try: () =>
                  new Promise<void>((resolve, reject) => {
                    state.queuedWhileStarting.push({
                      text,
                      source,
                      acceptance: { resolve, reject },
                    });
                    emit({
                      _tag: "QueueChanged",
                      queued: state.queuedWhileStarting.map((queued) => ({
                        text: queued.text,
                        kind: "steer" as const,
                      })),
                    });
                  }),
                catch: (error) =>
                  new SendError({ message: boundedError(error) }),
              });
            }
            state.queuedWhileStarting.push({ text, source });
            emit({
              _tag: "QueueChanged",
              queued: state.queuedWhileStarting.map((queued) => ({
                text: queued.text,
                kind: "steer" as const,
              })),
            });
            return Effect.void;
          }
          if (session.isStreaming) {
            // Teamlead guidance retains provenance as a custom message;
            // takeover/user input remains an ordinary steering message.
            return Effect.tryPromise({
              try: () =>
                source === "teamlead"
                  ? sendGuidanceDuringRun(text)
                  : session.steer(text),
              catch: (error) =>
                new SendError({ message: boundedError(error) }),
            }).pipe(Effect.asVoid);
          }
          if (source === "teamlead") {
            return Effect.tryPromise({
              try: () => startGuidanceRun(text),
              catch: (error) =>
                new SendError({ message: boundedError(error) }),
            }).pipe(Effect.asVoid);
          }
          return Effect.tryPromise({
            try: () => startRun(text),
            catch: (error) => new SendError({ message: boundedError(error) }),
          }).pipe(Effect.asVoid);
        }),
      reply: (requestId, text) =>
        Effect.suspend((): Effect.Effect<void, ReplyError> => {
          if (state.closed) {
            return new ReplyError({ message: "Subagent session is closed." });
          }
          try {
            validateCommunicationText(text);
            pendingQuestions.reply(requestId, text);
            return Effect.void;
          } catch (error) {
            return new ReplyError({ message: boundedError(error) });
          }
        }),
      interrupt: Effect.promise(async () => {
        if (state.closed) return;
        state.cancelling = true;
        state.startCancelled = true;
        backgroundActivity.cancelPending();
        toolInputs.clear();
        for (const queued of state.queuedWhileStarting.splice(0)) {
          queued.acceptance?.reject(new Error("Subagent run was interrupted"));
        }
        emit({ _tag: "QueueChanged", queued: [] });
        try {
          session.clearQueue();
        } catch {
          // Abort regardless.
        }
        await session.abort().catch(() => undefined);
        // Only resolve once streaming has actually stopped: reporting the
        // interrupt as complete while the run keeps working would let the
        // manager settle a run that is still mutating the workspace. The
        // manager bounds this effect at 5s and force-disposes on timeout.
        while (!state.closed && session.isStreaming) {
          await new Promise((resolve) => setTimeout(resolve, 50));
        }
        // No streaming run means no agent_settled will arrive; emit the
        // terminal event (once) so the run cannot look running forever.
        if (!state.closed && !state.settled) {
          state.settled = true;
          emit({ _tag: "RunSettled", outcome: { _tag: "Interrupted" } });
        }
        state.cancelling = false;
      }),
    } satisfies SubagentSession;
  });

export const piBackend: SubagentBackend = {
  name: "pi",
  capabilities: {
    steering: true,
    requestReply: true,
    modelSelection: true,
    reasoningEffort: true,
  },
  // In-process SDK: always available.
  available: Effect.succeed(true),
  spawn: makePiSession,
};
