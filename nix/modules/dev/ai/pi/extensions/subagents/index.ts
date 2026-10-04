/**
 * Subagents use GPT-5.6 Sol for coding and GPT-6 Astra for other tasks.
 *
 * Tools (for the parent LLM):
 * - subagent_spawn: fire-and-forget spawn (prompt, name, working_dir,
 *   model, reasoning_effort, allowed_subagents_depth). Max 4 running at once.
 * - subagent_wait: register a nonblocking wait; results arrive individually.
 * - subagent_send/subagent_reply: message children and answer questions.
 * - subagent_cancel: stop one or more running subagents.
 * - subagent_check: peek at a subagent's status and recent activity.
 * - subagent_list: list all subagents.
 *
 * Unawaited subagents queue their result as a follow-up message when they
 * settle. `/subagents` opens a picker + full interactive takeover view.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { StringEnum } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  ExtensionUIContext,
} from "@earendil-works/pi-coding-agent";
import {
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
  formatSize,
  getAgentDir,
  getMarkdownTheme,
  keyHint,
  ProjectTrustStore,
  truncateHead,
} from "@earendil-works/pi-coding-agent";
import { Box, Markdown, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { prepareAsyncWait } from "./src/async-wait.ts";
import { deriveBtwTitle, isModelVisible } from "./src/by-the-way.ts";
import {
  formatElapsed,
  latestText,
  REASONING_EFFORTS,
  subagentCompletionId,
  type ReasoningEffort,
  type SubagentSnapshot,
} from "./src/domain.ts";
import {
  formatActivityStatus,
  formatContextUtilization,
} from "./src/format.ts";
import { SubagentManager, type SubagentManagerShape } from "./src/manager.ts";
import {
  buildSubagentResultMessage,
  buildSubagentSpawnResult,
  SUBAGENT_CANCEL_PARAMETER_DESCRIPTIONS,
  SUBAGENT_CANCEL_TOOL_DESCRIPTION,
  SUBAGENT_CHECK_PARAMETER_DESCRIPTIONS,
  SUBAGENT_CHECK_TOOL_DESCRIPTION,
  SUBAGENT_LIST_TOOL_DESCRIPTION,
  SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS,
  SUBAGENT_REPLY_TOOL_DESCRIPTION,
  SUBAGENT_SEND_PARAMETER_DESCRIPTIONS,
  SUBAGENT_SEND_TOOL_DESCRIPTION,
  SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS,
  SUBAGENT_SPAWN_PROMPT_GUIDELINES,
  SUBAGENT_SPAWN_PROMPT_SNIPPET,
  SUBAGENT_SPAWN_TOOL_DESCRIPTION,
  SUBAGENT_WAIT_PARAMETER_DESCRIPTIONS,
  SUBAGENT_WAIT_TOOL_DESCRIPTION,
} from "./src/prompt.ts";
import { createDeferredResultDelivery } from "./src/result-delivery.ts";
import {
  checkpointFromSnapshot,
  isRecoverableCheckpoint,
  recoveryCheckpointsFromEntries,
  recoveryCompletionId,
  recoveryPublicIdsFromEntries,
  SUBAGENT_RECOVERY_BOUNDARY_ENTRY_TYPE,
  SUBAGENT_RECOVERY_ENTRY_TYPE,
  type RecoveryCheckpointStatus,
  type SubagentRecoveryCheckpoint,
} from "./src/recovery.ts";
import {
  createSubagentRuntime,
  runTool,
  type SubagentRuntime,
} from "./src/runtime.ts";
import {
  subagentDepthLimitFromEntries,
  validateRequestedSubagentDepth,
} from "./src/subagent-depth.ts";
import {
  resolveSubagentTreeRegistry,
  type SubagentTreeRegistry,
  type SubagentTreeView,
} from "./src/subagent-tree.ts";
import {
  createRunningSubagentEditorFactory,
  RUNNING_SUBAGENTS_HISTORY_WIDGET_KEY,
  RUNNING_SUBAGENTS_WIDGET_KEY,
  RunningSubagentController,
  RunningSubagentHistoryPane,
  RunningSubagentsPane,
  sessionPromptHistory,
} from "./src/ui/running-subagents.ts";
import { openSubagentPicker, openSubagentTakeover } from "./src/ui/takeover.ts";
import {
  renderCommunicationToolCall,
  renderCommunicationToolResult,
} from "./src/ui/communication.ts";
import { sanitizeText } from "./src/ui/transcript.ts";

const CODING_MODEL = "openai-codex/gpt-5.6-sol";
const GENERAL_MODEL = "openai-codex/gpt-6-astra";
const SUBAGENT_MODELS = [CODING_MODEL, GENERAL_MODEL] as const;
const SUBAGENT_OUTPUT_MAX_BYTES = 24 * 1024;
const SUBAGENT_MESSAGE_MAX_BYTES = 16 * 1024;

interface SpawnToolPreparedArgs {
  readonly prompt: string;
  readonly name: string;
  readonly model?: (typeof SUBAGENT_MODELS)[number];
  readonly working_dir?: string;
  readonly reasoning_effort?: ReasoningEffort;
  readonly allowed_subagents_depth?: number;
}

interface SubagentMessageData {
  readonly id: string;
  readonly title: string;
  readonly run: number;
  readonly messageId: string;
  readonly requestId?: string;
  readonly kind: "update" | "question" | "resolution";
  readonly text: string;
}

interface BtwResultData {
  readonly id: string;
  readonly title: string;
  readonly run?: number;
  readonly status: SubagentSnapshot["status"];
  readonly errorText?: string;
  readonly prompt: string;
  readonly answer: string;
  readonly sessionFilePath?: string;
}

function describeSubagent(snap: SubagentSnapshot) {
  const details = [
    `${snap.backend}: ${snap.meta.modelLabel ?? "?"}`,
    formatContextUtilization(snap.usage),
    formatElapsed(snap),
    snap.allowedSubagentsDepth > 0
      ? `descendant depth ${snap.allowedSubagentsDepth}`
      : undefined,
    snap.cwd,
  ].filter(Boolean);
  const waiting =
    snap.pendingQuestions.length > 0
      ? `, awaiting ${snap.pendingQuestions.length} repl${snap.pendingQuestions.length === 1 ? "y" : "ies"}`
      : "";
  return `${snap.id} [${snap.status}] "${snap.title}" (run ${snap.run}${waiting}; ${details.join(", ")})`;
}

function truncatedOutput(
  snap: SubagentSnapshot,
  maxBytes = SUBAGENT_OUTPUT_MAX_BYTES,
): string {
  const output = snap.finalText || "(no output)";
  const truncation = truncateHead(output, {
    maxBytes: Math.min(maxBytes, DEFAULT_MAX_BYTES),
    maxLines: Math.min(600, DEFAULT_MAX_LINES),
  });
  let text = truncation.content;
  if (truncation.truncated) {
    text += `\n\n[Output truncated: ${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)} shown. Full transcript in session file: ${snap.meta.sessionFilePath ?? "?"}]`;
  }
  return text;
}

/**
 * Same-directory children inherit the live parent decision. An alternate cwd
 * is trusted only when pi's persisted trust store explicitly trusts it (or a
 * containing directory); unreadable/invalid trust data fails closed.
 */
function resolveChildProjectTrust(options: {
  parentCwd: string;
  childCwd: string;
  parentTrusted: boolean;
}) {
  if (path.resolve(options.childCwd) === path.resolve(options.parentCwd)) {
    return options.parentTrusted;
  }
  try {
    const trustStore = new ProjectTrustStore(getAgentDir());
    return trustStore.get(options.childCwd) === true;
  } catch {
    return false;
  }
}

export default function (pi: ExtensionAPI) {
  let runtime: SubagentRuntime | undefined;
  let managerPromise: Promise<SubagentManagerShape> | undefined;
  let sessionContext: ExtensionContext | undefined;
  let ui: ExtensionUIContext | undefined;
  let unsubStatus: (() => void) | undefined;
  let runningPaneCleanup: ((restoreEditor?: boolean) => void) | undefined;
  let pendingRunningPaneInstall: (() => void) | undefined;
  let runningPaneController: RunningSubagentController | undefined;
  let treeRegistry: SubagentTreeRegistry | undefined;
  let treeView: SubagentTreeView | undefined;
  let unregisterTreeCoordinator: (() => void) | undefined;
  const resultDelivery =
    createDeferredResultDelivery<SubagentSnapshot>(subagentCompletionId);

  const isCoordinatorSession = () =>
    pi.getAllTools().some((tool) => tool.name === "subagent_spawn");

  const appendRecoveryCheckpoint = (
    snapshot: SubagentSnapshot,
    status: RecoveryCheckpointStatus = snapshot.status,
    terminal?: { readonly suppressed: boolean },
  ) => {
    if (!sessionContext || !isCoordinatorSession()) return;
    const checkpoint = checkpointFromSnapshot(snapshot, status);
    if (!checkpoint) return;
    const data: SubagentRecoveryCheckpoint = terminal
      ? {
          ...checkpoint,
          resultText: truncatedOutput(snapshot),
          delivery: terminal.suppressed ? "suppressed" : "pending",
        }
      : checkpoint;
    pi.appendEntry<SubagentRecoveryCheckpoint>(
      SUBAGENT_RECOVERY_ENTRY_TYPE,
      data,
    );
  };

  const getRuntime = () => (runtime ??= createSubagentRuntime());

  /** Resolve the manager service once per runtime and wire the extension hooks. */
  const getManager = () => {
    managerPromise ??= getRuntime()
      .runPromise(SubagentManager)
      .then((manager) => {
        manager.view.setOnSettled(onSettled);
        manager.view.setOnMessage(onSubagentMessage);
        manager.view.setOnLifecycle((snapshot) => {
          // Terminal checkpoints need callback suppression/output data, which
          // is available in onSettled immediately after this lifecycle hook.
          if (snapshot.status === "running") appendRecoveryCheckpoint(snapshot);
        });
        unsubStatus?.();
        unsubStatus = manager.view.subscribe(() => updateStatus(manager));
        updateStatus(manager);
        return manager;
      });
    return managerPromise;
  };

  const bindTreeCoordinator = (
    ctx: ExtensionContext,
    manager: SubagentManagerShape,
  ): SubagentTreeView => {
    unregisterTreeCoordinator?.();
    treeRegistry ??= resolveSubagentTreeRegistry(pi);
    const registration = treeRegistry.register(
      ctx.sessionManager.getSessionId(),
      manager.view,
    );
    unregisterTreeCoordinator = registration.unregister;
    treeView = registration.view;
    return registration.view;
  };

  const updateStatus = (manager: SubagentManagerShape) => {
    if (!ui) return;
    const subs = manager.view.list();
    if (subs.length === 0) {
      ui.setStatus("subagents", undefined);
      return;
    }
    const running = subs.filter((snap) => snap.status === "running").length;
    const failed = subs.filter((snap) => snap.status === "error").length;
    const done = subs.length - running - failed;
    const awaitingReply = subs.reduce(
      (total, snap) => total + snap.pendingQuestions.length,
      0,
    );
    ui.setStatus(
      "subagents",
      formatActivityStatus(ui.theme, {
        running,
        done,
        failed,
        awaitingReply,
      }),
    );
  };

  const deliverResult = (snap: SubagentSnapshot) => {
    pi.sendMessage(
      {
        customType: "subagent-result",
        content: buildSubagentResultMessage({
          id: snap.id,
          title: snap.title,
          status: snap.status,
          errorText: snap.errorText,
          output: truncatedOutput(snap),
        }),
        display: true,
        details: {
          id: snap.id,
          title: snap.title,
          status: snap.status,
          run: snap.run,
          completionId: subagentCompletionId(snap),
        },
      },
      { deliverAs: "followUp", triggerTurn: true },
    );
  };

  const deliverRecoveredResult = (checkpoint: SubagentRecoveryCheckpoint) => {
    if (checkpoint.origin === "btw") {
      pi.appendEntry<BtwResultData>("btw-result", {
        id: checkpoint.id,
        title: checkpoint.title,
        run: checkpoint.run,
        status: checkpoint.status === "done" ? "done" : "error",
        errorText: checkpoint.errorText,
        prompt: checkpoint.prompt,
        answer: checkpoint.resultText ?? "(no output)",
        sessionFilePath: checkpoint.sessionFilePath,
      });
      return;
    }
    const status = checkpoint.status === "done" ? "done" : "error";
    pi.sendMessage(
      {
        customType: "subagent-result",
        content: buildSubagentResultMessage({
          id: checkpoint.id,
          title: checkpoint.title,
          status,
          errorText: checkpoint.errorText,
          output: checkpoint.resultText ?? "(no output)",
        }),
        display: true,
        details: {
          id: checkpoint.id,
          title: checkpoint.title,
          status,
          run: checkpoint.run,
          completionId: `${checkpoint.id}:run-${checkpoint.run}`,
          recovered: true,
        },
      },
      { deliverAs: "followUp", triggerTurn: true },
    );
  };

  const restorePersistedSubagents = async (
    ctx: ExtensionContext,
    manager: SubagentManagerShape,
  ) => {
    const branch = ctx.sessionManager.getBranch();
    const checkpoints = recoveryCheckpointsFromEntries(branch);
    const currentDepthLimit = subagentDepthLimitFromEntries(
      ctx.sessionManager.getEntries(),
    );
    await getRuntime().runPromise(
      manager.reserveIds([...recoveryPublicIdsFromEntries(branch)]),
    );
    if (checkpoints.size === 0) return;

    const deferParentDelivery = (deliver: () => void) => {
      setTimeout(() => {
        if (sessionContext !== ctx) return;
        try {
          deliver();
        } catch {
          // The durable pending checkpoint remains retryable on next reopen.
        }
      }, 0);
    };

    const latestById = new Map<string, SubagentRecoveryCheckpoint>();
    for (const checkpoint of checkpoints.values()) {
      const previous = latestById.get(checkpoint.id);
      if (!previous || checkpoint.run >= previous.run) {
        latestById.set(checkpoint.id, checkpoint);
      }
    }

    const delivered = new Set<string>();
    const deliveredBtw = new Set<string>();
    const closedQuestions = new Set<string>();
    for (const entry of branch) {
      if (
        entry.type === "custom_message" &&
        entry.customType === "subagent-result"
      ) {
        const details = entry.details as { completionId?: unknown } | undefined;
        if (typeof details?.completionId === "string") {
          delivered.add(details.completionId);
        }
      } else if (
        entry.type === "custom_message" &&
        entry.customType === "subagent-message"
      ) {
        const details = entry.details as
          | { id?: unknown; requestId?: unknown; kind?: unknown }
          | undefined;
        if (
          details?.kind === "resolution" &&
          typeof details.id === "string" &&
          typeof details.requestId === "string"
        ) {
          closedQuestions.add(`${details.id}:${details.requestId}`);
        }
      } else if (entry.type === "custom" && entry.customType === "btw-result") {
        const data = entry.data as { id?: unknown; run?: unknown } | undefined;
        if (typeof data?.id === "string") {
          deliveredBtw.add(
            `${data.id}:run-${typeof data.run === "number" ? data.run : 1}`,
          );
        }
      }
    }

    let recovered = 0;
    for (const checkpoint of latestById.values()) {
      if (!isRecoverableCheckpoint(checkpoint)) continue;

      // The blocked tool promise was in the dead process and cannot be
      // reattached. Close the stale parent request explicitly; the recovered
      // child receives a normal continuation turn below.
      for (const question of checkpoint.pendingQuestions ?? []) {
        if (closedQuestions.has(`${checkpoint.id}:${question.requestId}`)) {
          continue;
        }
        const text = `Question ${question.requestId} was cancelled when the parent process ended. The recovered child is continuing from its durable checkpoint.`;
        deferParentDelivery(() =>
          pi.sendMessage(
            {
              customType: "subagent-message",
              content: `Subagent ${checkpoint.id} "${checkpoint.title}" question ${question.requestId} closed:\n\n${text}`,
              display: true,
              details: {
                id: checkpoint.id,
                title: checkpoint.title,
                run: checkpoint.run,
                messageId: `recovery-${question.messageId}`,
                requestId: question.requestId,
                kind: "resolution",
                text,
                recovered: true,
              } satisfies SubagentMessageData & { recovered: true },
            },
            { deliverAs: "steer", triggerTurn: true },
          ),
        );
      }

      const failRecovery = (error: unknown) => {
        const errorText = `Recovery failed: ${
          error instanceof Error ? error.message : String(error)
        }`;
        const failed: SubagentRecoveryCheckpoint = {
          ...checkpoint,
          status: "error",
          settledAt: Date.now(),
          errorText,
          resultText: errorText,
          delivery: "pending",
        };
        pi.appendEntry<SubagentRecoveryCheckpoint>(
          SUBAGENT_RECOVERY_ENTRY_TYPE,
          failed,
        );
        deferParentDelivery(() => deliverRecoveredResult(failed));
      };

      try {
        const allowedSubagentsDepth = validateRequestedSubagentDepth(
          checkpoint.allowedSubagentsDepth ?? 0,
          currentDepthLimit,
        );
        if (
          !fs.existsSync(checkpoint.cwd) ||
          !fs.statSync(checkpoint.cwd).isDirectory()
        ) {
          throw new Error(
            `working directory no longer exists: ${checkpoint.cwd}`,
          );
        }
        // SessionManager.open creates the explicit child path when a crash
        // happened before the first assistant message flushed the JSONL. The
        // repeated original prompt makes that empty-file recovery meaningful.
        if (
          fs.existsSync(checkpoint.sessionFilePath) &&
          !fs.statSync(checkpoint.sessionFilePath).isFile()
        ) {
          throw new Error(
            `child session path is not a file: ${checkpoint.sessionFilePath}`,
          );
        }
        await runTool(
          getRuntime(),
          manager.spawn("pi", {
            origin: checkpoint.origin,
            prompt: checkpoint.prompt,
            title: checkpoint.title,
            cwd: checkpoint.cwd,
            // Old checkpoints predate model selection and always used Sol.
            model: checkpoint.model ?? CODING_MODEL,
            allowedSubagentsDepth,
            resume: {
              id: checkpoint.id,
              sessionFilePath: checkpoint.sessionFilePath,
              run: checkpoint.run,
              createdAt: checkpoint.createdAt,
              queued: checkpoint.queued,
            },
            parent: {
              parentCwd: ctx.cwd,
              projectTrusted: resolveChildProjectTrust({
                parentCwd: ctx.cwd,
                childCwd: checkpoint.cwd,
                parentTrusted: ctx.isProjectTrusted(),
              }),
              inheritedModel: ctx.model
                ? { provider: ctx.model.provider, id: ctx.model.id }
                : undefined,
              inheritedThinkingLevel: pi.getThinkingLevel(),
              modelRegistry: ctx.modelRegistry,
              treeRegistry,
            },
          }),
        );
        recovered++;
      } catch (error) {
        failRecovery(error);
      }
    }

    // A terminal checkpoint is written before its callback is queued. If Pi
    // crashed in that gap, replay the callback unless its durable parent
    // message/entry is already present on this branch.
    for (const checkpoint of checkpoints.values()) {
      if (checkpoint.status !== "done" && checkpoint.status !== "error") {
        continue;
      }
      if (checkpoint.delivery !== "pending") continue;
      const completionId = recoveryCompletionId(checkpoint);
      const wasDelivered =
        checkpoint.origin === "btw"
          ? deliveredBtw.has(completionId)
          : delivered.has(completionId);
      if (!wasDelivered) {
        deferParentDelivery(() => deliverRecoveredResult(checkpoint));
      }
    }

    if (recovered > 0 && ctx.hasUI) {
      ctx.ui.notify(
        `Recovered ${recovered} running subagent${recovered === 1 ? "" : "s"}.`,
        "info",
      );
    }
  };

  const flushResults = () => {
    for (const snap of resultDelivery.drain()) {
      try {
        deliverResult(snap);
      } catch {
        resultDelivery.retry(snap);
      }
    }
  };

  const onSubagentMessage = (
    snap: SubagentSnapshot,
    message: SubagentSnapshot["communications"][number],
  ) => {
    if (!sessionContext || snap.origin !== "model") return;
    if (
      message.kind !== "update" &&
      message.kind !== "question" &&
      message.kind !== "resolution"
    )
      return;
    const question = message.kind === "question";
    const resolution = message.kind === "resolution";
    if (question || resolution) appendRecoveryCheckpoint(snap);
    let content = question
      ? `Subagent ${snap.id} "${snap.title}" asks the teamlead (request_id: ${message.requestId ?? "?"}):\n\n${message.text}`
      : resolution
        ? `Subagent ${snap.id} "${snap.title}" question ${message.requestId ?? "?"} closed:\n\n${message.text}`
        : `Subagent ${snap.id} "${snap.title}" sent an update:\n\n${message.text}`;
    if (question) {
      content += `\n\nReply with subagent_reply({ id: "${snap.id}", request_id: "${message.requestId ?? "?"}", message: "..." }).`;
    } else if (!resolution) {
      content += `\n\nUse subagent_send({ id: "${snap.id}", message: "..." }) if guidance is needed.`;
    }
    const data: SubagentMessageData = {
      id: snap.id,
      title: snap.title,
      run: snap.run,
      messageId: message.messageId,
      requestId: message.requestId,
      kind: message.kind,
      text: message.text,
    };
    try {
      pi.sendMessage(
        {
          customType: "subagent-message",
          content,
          display: true,
          details: data,
        },
        { deliverAs: "steer", triggerTurn: true },
      );
    } catch {
      // A stale parent session cannot receive communication; child state and
      // request timeout/cancellation remain authoritative.
    }
  };

  const deliverBtwResult = (snap: SubagentSnapshot) => {
    // appendEntry is a synchronous SessionManager operation and emits an
    // entry_appended event, so it is safe while the parent is streaming and
    // never enters the model's context or follow-up queue.
    pi.appendEntry<BtwResultData>("btw-result", {
      id: snap.id,
      title: snap.title,
      run: snap.run,
      status: snap.status,
      errorText: snap.errorText,
      prompt: snap.prompt,
      answer: truncatedOutput(snap),
      sessionFilePath: snap.meta.sessionFilePath,
    });
    ui?.notify(
      snap.status === "error"
        ? `by the way “${snap.title}” failed — reopen it with /subagents`
        : `by the way “${snap.title}” answered — reopen it with /subagents`,
      snap.status === "error" ? "error" : "info",
    );
  };

  const onSettled = (snap: SubagentSnapshot, suppressed: boolean) => {
    // A shutdown can settle children while disposing their scopes. Never
    // append into a session whose extension runtime is already closing.
    if (!sessionContext) return;
    appendRecoveryCheckpoint(snap, snap.status, {
      // By-the-way results are delivered even when tool-driven cancellation
      // suppresses model-facing callbacks.
      suppressed: snap.origin === "model" && suppressed,
    });
    if (snap.origin === "btw") {
      deliverBtwResult({ ...snap, meta: { ...snap.meta } });
      return;
    }
    if (suppressed) {
      resultDelivery.suppress({ ...snap, meta: { ...snap.meta } });
      return;
    }
    // Keep the result buffered while the parent is working, then flush it as
    // an individual follow-up when the parent settles. Defer a copy: the live
    // snapshot keeps mutating if the subagent is
    // restarted before the deferred result flushes.
    resultDelivery.defer({ ...snap, meta: { ...snap.meta } });
    if (sessionContext?.isIdle()) flushResults();
  };

  const installRunningPane = (
    ctx: ExtensionContext,
    view: SubagentTreeView,
    promptHistory: ReadonlyArray<string>,
  ) => {
    runningPaneCleanup?.();
    const controller = new RunningSubagentController(view);
    runningPaneController = controller;
    controller.setOnFocusChange((focused) => {
      // The working row describes the teamlead, not the child transcript being
      // inspected. Keep the bottom dock cleaner while child history is active.
      ctx.ui.setWorkingVisible(!focused);
    });
    const previousEditor = ctx.ui.getEditorComponent();
    const ownedEditor = createRunningSubagentEditorFactory(
      previousEditor,
      controller,
      promptHistory,
      (text) => ctx.ui.theme.fg("accent", text),
    );

    ctx.ui.setWidget(
      RUNNING_SUBAGENTS_HISTORY_WIDGET_KEY,
      (tui, theme) =>
        new RunningSubagentHistoryPane(tui, theme, controller, view),
      { placement: "aboveEditor" },
    );
    ctx.ui.setWidget(
      RUNNING_SUBAGENTS_WIDGET_KEY,
      (tui, theme) => new RunningSubagentsPane(tui, theme, controller, view),
      { placement: "belowEditor" },
    );
    ctx.ui.setEditorComponent(ownedEditor);

    runningPaneCleanup = (restoreEditor = true) => {
      controller.unfocus();
      if (runningPaneController === controller) {
        runningPaneController = undefined;
      }
      controller.setOnFocusChange(undefined);
      ctx.ui.setWidget(RUNNING_SUBAGENTS_HISTORY_WIDGET_KEY, undefined);
      ctx.ui.setWidget(RUNNING_SUBAGENTS_WIDGET_KEY, undefined);
      if (restoreEditor && ctx.ui.getEditorComponent() === ownedEditor) {
        ctx.ui.setEditorComponent(previousEditor);
      }
    };
  };

  pi.on("session_start", async (event, ctx) => {
    sessionContext = ctx;
    if (ctx.hasUI) ui = ctx.ui;
    // Child Pi sessions load this global extension too, but their orchestration
    // tools are excluded. Never recursively recover parent subagents there.
    if (!isCoordinatorSession()) return;

    const manager = await getManager();
    const sessionTreeView = bindTreeCoordinator(ctx, manager);
    if (event.reason === "fork") {
      // Forks/clones inherit the conversation but must not share ownership of
      // a mutable child JSONL with the source parent session.
      pi.appendEntry(SUBAGENT_RECOVERY_BOUNDARY_ENTRY_TYPE, { version: 1 });
    }
    await restorePersistedSubagents(ctx, manager);
    if (ctx.mode !== "tui") return;

    // On process startup Pi renders/restores prompt history after session_start,
    // so the newly installed editor receives it normally. Replacement/reload
    // flows render before rebinding extensions, so hydrate the fresh fallback.
    const promptHistory =
      event.reason === "startup"
        ? []
        : sessionPromptHistory(ctx.sessionManager.buildContextEntries());
    // Later session_start handlers, such as pi-atomic-images, replace the
    // editor outright. Wait until they finish, then decorate the final editor.
    pendingRunningPaneInstall = () => {
      // Session replacement may finish during asynchronous manager setup.
      if (sessionContext === ctx) {
        installRunningPane(ctx, sessionTreeView, promptHistory);
      }
    };
  });

  pi.on("resources_discover", () => {
    const install = pendingRunningPaneInstall;
    pendingRunningPaneInstall = undefined;
    install?.();
  });

  pi.on("agent_settled", flushResults);

  pi.on("session_tree", async (_event, ctx) => {
    if (!isCoordinatorSession()) return;

    // Tree navigation changes parent history in place without rebinding the
    // extension. Do not let children from the abandoned branch keep running
    // and append lifecycle/results onto the destination branch. Navigating the
    // tree deliberately abandons inherited child ownership; quit/resume and
    // reload are the flows that auto-continue it.
    // Pi keeps the editor factory installed during in-session tree rewinds.
    // Preserve this controller/factory instead of wrapping the current editor
    // again: other editor extensions may proxy our factory, and re-wrapping
    // that proxy creates a recursive handleInput chain.
    runningPaneController?.unfocus();
    ctx.ui.setWorkingVisible(true);
    sessionContext = undefined;
    resultDelivery.clear();
    unsubStatus?.();
    unsubStatus = undefined;
    unregisterTreeCoordinator?.();
    unregisterTreeCoordinator = undefined;
    treeView = undefined;
    ui?.setStatus("subagents", undefined);

    const closing = runtime;
    runtime = undefined;
    managerPromise = undefined;
    // Persist the destination-branch boundary before potentially slow child
    // disposal so a crash during teardown cannot transfer old ownership.
    pi.appendEntry(SUBAGENT_RECOVERY_BOUNDARY_ENTRY_TYPE, { version: 1 });
    await closing?.dispose();

    sessionContext = ctx;
    if (ctx.hasUI) ui = ctx.ui;
    const manager = await getManager();
    const sessionTreeView = bindTreeCoordinator(ctx, manager);
    await restorePersistedSubagents(ctx, manager);
    if (
      ctx.mode === "tui" &&
      sessionContext === ctx &&
      !runningPaneController
    ) {
      installRunningPane(
        ctx,
        sessionTreeView,
        sessionPromptHistory(ctx.sessionManager.buildContextEntries()),
      );
    }
  });

  pi.on("session_shutdown", async () => {
    pendingRunningPaneInstall = undefined;
    // Pi resets the editor after shutdown. Avoid instantiating the previous
    // editor factory just before that reset; only dispose our widget here.
    runningPaneCleanup?.(false);
    runningPaneCleanup = undefined;

    // Checkpoint before clearing the parent context or aborting children.
    // Graceful quit/reload/session replacement therefore looks exactly like a
    // hard crash to the next opener: the child JSONL is reopened and continued.
    const currentManager = await managerPromise?.catch(() => undefined);
    if (currentManager) {
      for (const snapshot of currentManager.view.list()) {
        if (snapshot.status !== "running") continue;
        try {
          appendRecoveryCheckpoint(snapshot, "suspended");
        } catch {
          // Shutdown remains best-effort; the previous running checkpoint is
          // still sufficient for crash-style recovery.
        }
      }
    }

    sessionContext = undefined;
    resultDelivery.clear();
    unsubStatus?.();
    unsubStatus = undefined;
    unregisterTreeCoordinator?.();
    unregisterTreeCoordinator = undefined;
    treeView = undefined;
    ui?.setStatus("subagents", undefined);
    ui = undefined;
    const closing = runtime;
    runtime = undefined;
    managerPromise = undefined;
    // Disposing the runtime runs the manager finalizer, which tears down all
    // subagent scopes (and, later, their real child processes).
    await closing?.dispose();
  });

  // --- Tools -------------------------------------------------------------

  pi.registerTool({
    name: "subagent_spawn",
    label: "Spawn Subagent",
    description: SUBAGENT_SPAWN_TOOL_DESCRIPTION,
    promptSnippet: SUBAGENT_SPAWN_PROMPT_SNIPPET,
    promptGuidelines: SUBAGENT_SPAWN_PROMPT_GUIDELINES,
    parameters: Type.Object({
      prompt: Type.String({
        description: SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS.prompt,
      }),
      name: Type.String({
        description: SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS.name,
      }),
      model: Type.Optional(
        StringEnum(SUBAGENT_MODELS, {
          description: SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS.model,
          default: CODING_MODEL,
        }),
      ),
      working_dir: Type.Optional(
        Type.String({
          description: SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS.workingDir,
        }),
      ),
      reasoning_effort: Type.Optional(
        StringEnum(REASONING_EFFORTS, {
          description: SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS.reasoningEffort,
        }),
      ),
      allowed_subagents_depth: Type.Optional(
        Type.Integer({
          minimum: 0,
          default: 0,
          description:
            SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS.allowedSubagentsDepth,
        }),
      ),
    }),
    prepareArguments(args) {
      if (!args || typeof args !== "object") {
        // SAFETY: Pi validates the prepared value against parameters before
        // execute; preserve invalid input so that validation rejects it.
        return args as SpawnToolPreparedArgs;
      }
      // SAFETY: Only named properties are read from this object, as unknown.
      const legacy = args as Record<string, unknown>;
      if (legacy.harness !== undefined && legacy.harness !== "pi") {
        throw new Error(
          `Only the pi harness is supported; received ${String(legacy.harness)}.`,
        );
      }
      const { harness: _harness, title, ...current } = legacy;
      // SAFETY: This only migrates legacy field names. Pi's subsequent schema
      // validation checks required fields and the two allowed model ids.
      return {
        ...current,
        ...(current.name === undefined && typeof title === "string"
          ? { name: title }
          : {}),
      } as unknown as SpawnToolPreparedArgs;
    },
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const allowedSubagentsDepth = validateRequestedSubagentDepth(
        params.allowed_subagents_depth ?? 0,
        subagentDepthLimitFromEntries(ctx.sessionManager.getEntries()),
      );
      const manager = await getManager();
      const harness = "pi" as const;

      const cwd = path.resolve(ctx.cwd, params.working_dir ?? ".");
      if (!fs.existsSync(cwd) || !fs.statSync(cwd).isDirectory()) {
        throw new Error(`working_dir is not a directory: ${cwd}`);
      }

      const title = params.name.trim().slice(0, 160) || "subagent";
      const snap = await runTool(
        getRuntime(),
        manager.spawn(harness, {
          prompt: params.prompt,
          title,
          cwd,
          model: params.model ?? CODING_MODEL,
          reasoningEffort: params.reasoning_effort,
          allowedSubagentsDepth,
          parent: {
            parentCwd: ctx.cwd,
            projectTrusted: resolveChildProjectTrust({
              parentCwd: ctx.cwd,
              childCwd: cwd,
              parentTrusted: ctx.isProjectTrusted(),
            }),
            inheritedModel: ctx.model
              ? { provider: ctx.model.provider, id: ctx.model.id }
              : undefined,
            inheritedThinkingLevel: pi.getThinkingLevel(),
            modelRegistry: ctx.modelRegistry,
            treeRegistry,
          },
        }),
        { signal, interruptMessage: "Subagent spawn aborted." },
      );

      return {
        content: [
          {
            type: "text",
            text: buildSubagentSpawnResult({
              id: snap.id,
              title: snap.title,
              harness,
              modelLabel: snap.meta.modelLabel ?? "?",
              cwd,
              allowedSubagentsDepth,
            }),
          },
        ],
        details: {
          id: snap.id,
          title: snap.title,
          cwd,
          harness,
          model: snap.meta.modelLabel,
          allowedSubagentsDepth,
          completionId: subagentCompletionId(snap),
        },
      };
    },
  });

  pi.registerTool({
    name: "subagent_wait",
    label: "Wait for Subagents",
    description: SUBAGENT_WAIT_TOOL_DESCRIPTION,
    parameters: Type.Object({
      ids: Type.Array(Type.String(), {
        maxItems: 64,
        description: SUBAGENT_WAIT_PARAMETER_DESCRIPTIONS.ids,
      }),
    }),
    async execute(_toolCallId, params) {
      const manager = await getManager();
      const ids = [...new Set(params.ids)];
      if (ids.length === 0)
        throw new Error("Provide at least one subagent id.");
      const known = manager.view
        .list()
        .filter(isModelVisible)
        .map((snap) => snap.id);
      const snapshots = ids.map((id) => manager.view.get(id));
      const unknown = ids.filter((id, index) => {
        const snap = snapshots[index];
        return !snap || !isModelVisible(snap);
      });
      if (unknown.length > 0) {
        throw new Error(
          `Unknown subagent id(s): ${unknown.join(", ")}. Known: ${known.join(", ") || "none"}.`,
        );
      }

      const visible = snapshots as SubagentSnapshot[];
      const wait = prepareAsyncWait(visible, resultDelivery);
      return {
        content: [{ type: "text", text: wait.text }],
        details: wait.details,
      };
    },
  });

  pi.registerTool({
    name: "subagent_send",
    label: "Message Subagent",
    description: SUBAGENT_SEND_TOOL_DESCRIPTION,
    parameters: Type.Object({
      id: Type.String({
        description: SUBAGENT_SEND_PARAMETER_DESCRIPTIONS.id,
      }),
      message: Type.String({
        description: SUBAGENT_SEND_PARAMETER_DESCRIPTIONS.message,
      }),
    }),
    renderCall(args, theme) {
      return renderCommunicationToolCall(
        { id: args.id, kind: "guidance" },
        theme,
      );
    },
    renderResult(result, { expanded, isPartial }, theme, context) {
      const args = context.args as { message?: string };
      const summary =
        result.content.find(
          (part): part is { type: "text"; text: string } =>
            part.type === "text",
        )?.text ?? "Message send finished.";
      return renderCommunicationToolResult(
        {
          summary,
          message: args.message,
          expanded,
          isPartial,
          isError: context.isError,
        },
        theme,
      );
    },
    async execute(_toolCallId, params, signal) {
      const manager = await getManager();
      const snap = manager.view.get(params.id);
      if (!snap || !isModelVisible(snap)) {
        const known = manager.view
          .list()
          .filter(isModelVisible)
          .map((entry) => entry.id);
        throw new Error(
          `Unknown subagent id "${params.id}". Known: ${known.join(", ") || "none"}.`,
        );
      }
      const message = params.message;
      if (!message.trim()) throw new Error("message must not be empty.");
      if (Buffer.byteLength(message, "utf8") > SUBAGENT_MESSAGE_MAX_BYTES) {
        throw new Error(
          `message exceeds the ${SUBAGENT_MESSAGE_MAX_BYTES}-byte limit.`,
        );
      }
      const acceptance = await runTool(
        getRuntime(),
        manager.message(params.id, message),
        { signal, interruptMessage: "Message send aborted." },
      );
      return {
        content: [
          {
            type: "text",
            text: `Message accepted for ${snap.id}. It will arrive at the next safe boundary of an active run, or start a new run if the child has settled.`,
          },
        ],
        details: {
          id: snap.id,
          accepted: true,
          statusAtAcceptance: acceptance.statusAtAcceptance,
          runAtAcceptance: acceptance.runAtAcceptance,
          startsNewRun: acceptance.startsNewRun,
          completionId: acceptance.completionId,
        },
      };
    },
  });

  pi.registerTool({
    name: "subagent_reply",
    label: "Reply to Subagent",
    description: SUBAGENT_REPLY_TOOL_DESCRIPTION,
    parameters: Type.Object({
      id: Type.String({
        description: SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS.id,
      }),
      request_id: Type.String({
        description: SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS.requestId,
      }),
      message: Type.String({
        description: SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS.message,
      }),
    }),
    renderCall(args, theme) {
      return renderCommunicationToolCall(
        {
          id: args.id,
          requestId: args.request_id,
          kind: "reply",
        },
        theme,
      );
    },
    renderResult(result, { expanded, isPartial }, theme, context) {
      const args = context.args as { message?: string };
      const summary =
        result.content.find(
          (part): part is { type: "text"; text: string } =>
            part.type === "text",
        )?.text ?? "Reply finished.";
      return renderCommunicationToolResult(
        {
          summary,
          message: args.message,
          expanded,
          isPartial,
          isError: context.isError,
        },
        theme,
      );
    },
    async execute(_toolCallId, params, signal) {
      const manager = await getManager();
      const snap = manager.view.get(params.id);
      if (!snap || !isModelVisible(snap)) {
        const known = manager.view
          .list()
          .filter(isModelVisible)
          .map((entry) => entry.id);
        throw new Error(
          `Unknown subagent id "${params.id}". Known: ${known.join(", ") || "none"}.`,
        );
      }
      const message = params.message;
      if (!message.trim()) throw new Error("message must not be empty.");
      if (Buffer.byteLength(message, "utf8") > SUBAGENT_MESSAGE_MAX_BYTES) {
        throw new Error(
          `message exceeds the ${SUBAGENT_MESSAGE_MAX_BYTES}-byte limit.`,
        );
      }
      await runTool(
        getRuntime(),
        manager.reply(params.id, params.request_id, message),
        { signal, interruptMessage: "Reply aborted." },
      );
      return {
        content: [
          {
            type: "text",
            text: `Reply delivered to ${snap.id} question ${params.request_id}. The waiting child tool can continue.`,
          },
        ],
        details: {
          id: snap.id,
          run: snap.run,
          requestId: params.request_id,
          delivered: true,
        },
      };
    },
  });

  pi.registerTool({
    name: "subagent_cancel",
    label: "Cancel Subagents",
    description: SUBAGENT_CANCEL_TOOL_DESCRIPTION,
    parameters: Type.Object({
      ids: Type.Array(Type.String(), {
        description: SUBAGENT_CANCEL_PARAMETER_DESCRIPTIONS.ids,
      }),
    }),
    async execute(_toolCallId, params, signal) {
      const manager = await getManager();
      const ids = [...new Set(params.ids)];
      if (ids.length === 0)
        throw new Error("Provide at least one subagent id.");

      const known = manager.view
        .list()
        .filter(isModelVisible)
        .map((snap) => snap.id);
      const unknown = ids.filter((id) => {
        const snap = manager.view.get(id);
        return !snap || !isModelVisible(snap);
      });
      if (unknown.length > 0) {
        throw new Error(
          `Unknown subagent id(s): ${unknown.join(", ")}. Known: ${known.join(", ") || "none"}.`,
        );
      }

      const report = await runTool(getRuntime(), manager.cancel(ids), {
        signal,
        interruptMessage: "Subagent cancellation aborted.",
      });

      const lines = report.map((entry) =>
        entry.cancelled
          ? `Cancelled ${entry.id} "${entry.title}".`
          : `${entry.id} "${entry.title}" was already ${entry.status}.`,
      );

      return {
        content: [{ type: "text", text: lines.join("\n") }],
        details: {
          results: report.map((entry) => ({
            id: entry.id,
            title: entry.title,
            status: entry.status,
            cancelled: entry.cancelled,
            completionId: entry.completionId,
          })),
        },
      };
    },
  });

  pi.registerTool({
    name: "subagent_check",
    label: "Check Subagent",
    description: SUBAGENT_CHECK_TOOL_DESCRIPTION,
    parameters: Type.Object({
      id: Type.String({
        description: SUBAGENT_CHECK_PARAMETER_DESCRIPTIONS.id,
      }),
    }),
    async execute(_toolCallId, params) {
      const manager = await getManager();
      const snap = manager.view.get(params.id);
      if (!snap || !isModelVisible(snap)) {
        const known = manager.view
          .list()
          .filter(isModelVisible)
          .map((s) => s.id);
        throw new Error(
          `Unknown subagent id "${params.id}". Known: ${known.join(", ") || "none"}.`,
        );
      }

      let text = `${describeSubagent(snap)}\nRun: ${snap.run}\nTurns: ${snap.turns}`;
      if (snap.errorText) text += `\nError: ${snap.errorText}`;
      if (snap.pendingQuestions.length > 0) {
        text += "\n\nAwaiting teamlead replies:";
        for (const question of snap.pendingQuestions) {
          text += `\n- ${question.requestId}: ${question.question}`;
        }
      }
      if (snap.queued.length > 0) {
        text += `\nQueued messages: ${snap.queued.length}`;
      }

      const output = latestText(snap);
      if (output) {
        const preview = truncateHead(output, { maxBytes: 2048, maxLines: 20 });
        text += `\n\nLatest output:\n${preview.content}`;
        if (preview.truncated) text += "\n[...]";
      } else if (snap.status === "running") {
        text += "\n\n(no text output yet)";
      }

      return {
        content: [{ type: "text", text }],
        details: {
          id: snap.id,
          run: snap.run,
          status: snap.status,
          turns: snap.turns,
          allowedSubagentsDepth: snap.allowedSubagentsDepth,
          queuedMessages: snap.queued.length,
          pendingQuestions: snap.pendingQuestions.map((question) => ({
            requestId: question.requestId,
            question: question.question,
            createdAt: question.createdAt,
          })),
        },
      };
    },
  });

  pi.registerTool({
    name: "subagent_list",
    label: "List Subagents",
    description: SUBAGENT_LIST_TOOL_DESCRIPTION,
    parameters: Type.Object({}),
    async execute() {
      const manager = await getManager();
      const subs = manager.view.list().filter(isModelVisible);
      const text =
        subs.length === 0
          ? "No subagents."
          : subs.map((snap) => describeSubagent(snap)).join("\n");
      return {
        content: [{ type: "text", text }],
        details: {
          subagents: subs.map((snap) => ({
            id: snap.id,
            title: snap.title,
            harness: snap.backend,
            run: snap.run,
            status: snap.status,
            allowedSubagentsDepth: snap.allowedSubagentsDepth,
            pendingReplies: snap.pendingQuestions.length,
          })),
        },
      };
    },
  });

  // --- Result and communication message rendering -----------------------

  pi.registerMessageRenderer(
    "subagent-message",
    (message, { expanded, outputPad }, theme) => {
      const details = (message.details ?? {}) as Partial<SubagentMessageData>;
      const question = details.kind === "question";
      const resolution = details.kind === "resolution";
      const icon = question
        ? theme.fg("warning", "?")
        : resolution
          ? theme.fg("muted", "×")
          : theme.fg("accent", "↑");
      const header =
        `${icon} ` +
        theme.fg("accent", theme.bold(`subagent ${details.id ?? "?"}`)) +
        theme.fg(
          "muted",
          ` · ${details.title ?? ""} · ${question ? `question ${details.requestId ?? "?"}` : resolution ? `question ${details.requestId ?? "?"} closed` : "update"}`,
        );
      const body = sanitizeText(
        typeof details.text === "string"
          ? details.text
          : typeof message.content === "string"
            ? message.content.split("\n").slice(1).join("\n").trim()
            : "",
      );
      const box = new Box(outputPad, 0, (text) =>
        theme.bg("customMessageBg", text),
      );
      box.addChild(new Text(header, 0, 0));
      if (expanded) {
        box.addChild(new Markdown(body, 0, 0, getMarkdownTheme()));
        return box;
      }
      const lines = body.split("\n");
      let text = "";
      for (const line of lines.slice(0, 8))
        text += `${text ? "\n" : ""}${theme.fg("customMessageText", line)}`;
      if (lines.length > 8)
        text += `\n${theme.fg("dim", `... (${keyHint("app.tools.expand", "to expand")})`)}`;
      box.addChild(new Text(text, 0, 0));
      return box;
    },
  );

  pi.registerMessageRenderer(
    "subagent-result",
    (message, { expanded }, theme) => {
      const details = (message.details ?? {}) as {
        id?: string;
        title?: string;
        status?: string;
        run?: number;
      };
      const failed = details.status === "error";
      const icon = failed ? theme.fg("error", "x") : theme.fg("success", "■");
      const runLabel =
        typeof details.run === "number" ? ` · run ${details.run}` : "";
      const header =
        `${icon} ` +
        theme.fg("accent", theme.bold(`subagent ${details.id ?? "?"}`)) +
        theme.fg(
          "muted",
          ` · ${details.title ?? ""}${runLabel} · ${failed ? "failed" : "finished"}`,
        );

      const content =
        typeof message.content === "string" ? message.content : "";
      // Remove only the summary line. The following Error line (when present)
      // is part of the actual result and must remain visible.
      const body = content.split("\n").slice(1).join("\n").trim();

      if (expanded) {
        const md = new Markdown(`${body}`, 0, 0, getMarkdownTheme());
        const container = new Text(header, 0, 0);
        return {
          render: (width: number) => [
            ...container.render(width),
            ...md.render(width),
          ],
          invalidate: () => {
            container.invalidate();
            md.invalidate();
          },
        };
      }

      const previewLines = body.split("\n").slice(0, 8);
      let text = header;
      for (const line of previewLines)
        text += `\n${theme.fg("toolOutput", line)}`;
      if (body.split("\n").length > 8)
        text += `\n${theme.fg("dim", "... (ctrl+o to expand)")}`;
      return new Text(text, 0, 0);
    },
  );

  pi.registerEntryRenderer<BtwResultData>(
    "btw-result",
    (entry, { expanded }, theme) => {
      const data = entry.data;
      const failed = data?.status === "error";
      const icon = failed ? theme.fg("error", "x") : theme.fg("success", "■");
      const header =
        `${icon} ` +
        theme.fg("accent", theme.bold(`by the way · ${data?.title ?? "?"}`)) +
        theme.fg(
          "muted",
          ` · ${failed ? "failed" : "answered"} · ${data?.id ?? "?"}`,
        );
      const body = [
        data?.errorText ? `Error: ${data.errorText}` : "",
        data?.answer ?? "(no answer)",
      ]
        .filter(Boolean)
        .join("\n\n");

      if (expanded) {
        const md = new Markdown(body, 0, 0, getMarkdownTheme());
        const container = new Text(header, 0, 0);
        return {
          render: (width: number) => [
            ...container.render(width),
            ...md.render(width),
          ],
          invalidate: () => {
            container.invalidate();
            md.invalidate();
          },
        };
      }

      const lines = body.split("\n");
      let text = header;
      for (const line of lines.slice(0, 8))
        text += `\n${theme.fg("toolOutput", line)}`;
      if (lines.length > 8)
        text += `\n${theme.fg("dim", "... (ctrl+o to expand)")}`;
      return new Text(text, 0, 0);
    },
  );

  // --- Commands -----------------------------------------------------------

  const runByTheWay = async (rawArgs: string, ctx: ExtensionCommandContext) => {
    if (ctx.mode !== "tui") {
      if (ctx.hasUI)
        ctx.ui.notify("by the way is only available in the TUI", "error");
      return;
    }

    let prompt = rawArgs.trim();
    if (!prompt) {
      const input = await ctx.ui.input("by the way", "Ask a one-off question…");
      prompt = input?.trim() ?? "";
      if (!prompt) return;
    }

    const manager = await getManager();
    let snap: SubagentSnapshot;
    try {
      snap = await runTool(
        getRuntime(),
        manager.spawn("pi", {
          origin: "btw",
          prompt,
          title: deriveBtwTitle(prompt),
          cwd: ctx.cwd,
          model: GENERAL_MODEL,
          parent: {
            parentCwd: ctx.cwd,
            projectTrusted: ctx.isProjectTrusted(),
            inheritedModel: ctx.model
              ? { provider: ctx.model.provider, id: ctx.model.id }
              : undefined,
            inheritedThinkingLevel: pi.getThinkingLevel(),
            modelRegistry: ctx.modelRegistry,
            treeRegistry,
          },
        }),
      );
    } catch (error) {
      ctx.ui.notify(
        error instanceof Error ? error.message : String(error),
        "error",
      );
      return;
    }

    const currentTree = treeView ?? bindTreeCoordinator(ctx, manager);
    const key = currentTree.directKey(snap.id);
    if (key) {
      await openSubagentTakeover(ctx, currentTree, key, {
        badge: "by the way",
      });
    }
  };

  pi.registerCommand("btw", {
    description:
      "Ask a one-off side question while the main agent keeps working",
    handler: runByTheWay,
  });

  pi.registerCommand("subagents", {
    description: "List, inspect, and take over subagents",
    handler: async (_args, ctx) => {
      if (ctx.mode !== "tui") {
        if (ctx.hasUI)
          ctx.ui.notify(
            "Subagent takeover is only available in the TUI",
            "error",
          );
        return;
      }
      const manager = await getManager();
      const currentTree = treeView ?? bindTreeCoordinator(ctx, manager);
      if (currentTree.size() === 0) {
        ctx.ui.notify(
          "No subagents yet. The agent spawns them with subagent_spawn.",
          "info",
        );
        return;
      }
      await openSubagentPicker(ctx, currentTree);
    },
  });
}
