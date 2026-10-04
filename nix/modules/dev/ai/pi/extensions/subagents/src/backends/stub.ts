/**
 * Scripted stub sessions shared by all three backend implementations while
 * the real integrations are pending. A stub session:
 *
 * - streams a plausible turn (thinking deltas, one fake tool cycle, text
 *   deltas, usage ramp, a final assistant message, RunSettled) over a few
 *   seconds so streaming UI, wait, and the footer counters are observable;
 * - supports send() while running (queued-steer rendering) and while idle
 *   (fresh run);
 * - supports interrupt (RunSettled Interrupted -> status "error", matching v1);
 * - fails the run when the prompt starts with "FAIL:" (error-path testing);
 * - appends every event to a JSONL "session file" in tmpdir so the
 *   "full transcript in session file" pointers resolve.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { Cause, Scope } from "effect";
import { Duration, Effect, Fiber, Queue, Ref, Stream } from "effect";
import type { SubagentBackend, SubagentSession } from "../backend.ts";
import type {
  BackendName,
  QueuedMessage,
  SpawnTask,
  SubagentEvent,
  SubagentInputSource,
  SubagentMeta,
} from "../domain.ts";
import { ReplyError, SendError } from "../domain.ts";

export interface StubProfile {
  readonly backend: BackendName;
  readonly defaultModelLabel: string;
  readonly contextWindow: number;
  readonly toolName: string;
  /** Delay between scripted events; varies per backend so streams differ. */
  readonly cadenceMs: number;
}

const STUB_DIR = path.join(os.tmpdir(), "subagents-stub");
let sessionCounter = 0;

export function makeStubBackend(profile: StubProfile): SubagentBackend {
  return {
    name: profile.backend,
    capabilities: {
      steering: true,
      requestReply: true,
      modelSelection: true,
      reasoningEffort: true,
    },
    // Real impls probe binary-on-PATH / SDK import / credentials here.
    available: Effect.succeed(true),
    spawn: (task) => makeStubSession(profile, task),
  };
}

function firstLine(text: string): string {
  return (
    text
      .split("\n")
      .find((line) => line.trim())
      ?.trim() ?? ""
  );
}

function chunked(text: string, size: number): string[] {
  const chunks: string[] = [];
  for (let i = 0; i < text.length; i += size)
    chunks.push(text.slice(i, i + size));
  return chunks;
}

const makeStubSession = (
  profile: StubProfile,
  task: SpawnTask,
): Effect.Effect<SubagentSession, never, Scope.Scope> =>
  Effect.gen(function* () {
    const sessionId = `stub-${profile.backend}-${++sessionCounter}`;
    const sessionFile = path.join(STUB_DIR, `${sessionId}.jsonl`);

    const state = {
      meta: {
        backend: profile.backend,
        modelLabel: task.model ?? profile.defaultModelLabel,
        contextWindow: profile.contextWindow,
        sessionFilePath: sessionFile,
        nativeSessionId: sessionId,
      } satisfies SubagentMeta as SubagentMeta,
      pending: [] as Array<{
        readonly text: string;
        readonly source: "initial" | SubagentInputSource;
      }>,
      turnCount: 0,
      closed: false,
      /** True between the driver dequeuing a prompt and registering its turn fiber. */
      dispatching: false,
    };

    const events = yield* Queue.make<SubagentEvent, Cause.Done>();
    const inbox = yield* Queue.make<
      {
        readonly text: string;
        readonly source: "initial" | SubagentInputSource;
      },
      Cause.Done
    >();
    const activeTurn = yield* Ref.make<
      Fiber.Fiber<void, ReplyError> | undefined
    >(undefined);
    let communicationCounter = 0;
    let requestCounter = 0;
    const pendingReplies = new Map<
      string,
      {
        readonly messageId: string;
        readonly resume: (effect: Effect.Effect<string, ReplyError>) => void;
      }
    >();

    const emit = (event: SubagentEvent) =>
      Effect.suspend(() => {
        try {
          fs.appendFileSync(sessionFile, `${JSON.stringify(event)}\n`);
        } catch {
          // The fake session file is best-effort.
        }
        if (event._tag === "MetaChanged") {
          state.meta = { ...state.meta, ...event.meta };
        }
        return Queue.offer(events, event);
      }).pipe(Effect.asVoid);

    const pause = Effect.sleep(Duration.millis(profile.cadenceMs));

    const runTurn = (userText: string, turn: number) =>
      Effect.gen(function* () {
        yield* emit({ _tag: "RunStarted" });
        // Mirrors backends that emit optimistic and native lifecycle starts;
        // the manager must count one logical run, not two.
        yield* emit({ _tag: "RunStarted" });
        const failing = userText.trimStart().startsWith("FAIL:");
        let teamleadReply = "";
        if (
          (task.origin ?? "model") === "model" &&
          userText.trimStart().startsWith("ASK:")
        ) {
          const question = userText.trimStart().slice(4).trim() || "Need guidance";
          const requestId = `req-${++requestCounter}`;
          const messageId = `child-msg-${++communicationCounter}`;
          teamleadReply = yield* Effect.callback<string, ReplyError>((resume) => {
            pendingReplies.set(requestId, { messageId, resume });
            Queue.offerUnsafe(events, {
              _tag: "MessageToLead",
              message: {
                messageId,
                requestId,
                kind: "question",
                text: question,
                createdAt: Date.now(),
              },
            });
            return Effect.sync(() => {
              if (!pendingReplies.delete(requestId)) return;
              Queue.offerUnsafe(events, {
                _tag: "QuestionClosed",
                requestId,
                messageId: `child-msg-${++communicationCounter}`,
                outcome: "cancelled",
                createdAt: Date.now(),
              });
            });
          });
        } else if (
          (task.origin ?? "model") === "model" &&
          userText.trimStart().startsWith("UPDATE:")
        ) {
          yield* emit({
            _tag: "MessageToLead",
            message: {
              messageId: `child-msg-${++communicationCounter}`,
              kind: "update",
              text: userText.trimStart().slice(7).trim() || "Update",
              createdAt: Date.now(),
            },
          });
        }

        const thinking = "Looking at the task and planning an approach...";
        for (const delta of chunked(thinking, 16)) {
          yield* emit({ _tag: "AssistantDelta", kind: "thinking", delta });
          yield* pause;
        }

        const toolId = `${sessionId}-tool-${turn}`;
        const argsPreview = `{"command":"ls ${task.cwd}"}`;
        yield* emit({
          _tag: "AssistantMessage",
          parts: [
            { type: "thinking", text: thinking },
            {
              type: "text",
              text: `I'll run ${profile.toolName} to look around first.`,
            },
            { type: "toolCall", toolId, name: profile.toolName, argsPreview },
          ],
        });
        yield* emit({
          _tag: "ToolStart",
          toolId,
          name: profile.toolName,
          argsPreview,
        });
        yield* pause;
        yield* emit({
          _tag: "ToolUpdate",
          toolId,
          outputPreview: "src docs package.json",
        });
        yield* pause;
        yield* emit({
          _tag: "ToolEnd",
          toolId,
          name: profile.toolName,
          isError: false,
          outputPreview: "src docs package.json",
        });
        yield* emit({
          _tag: "UsageChanged",
          tokens: Math.min(profile.contextWindow, 2400 * (turn + 1)),
          contextWindow: profile.contextWindow,
        });

        if (failing) {
          yield* pause;
          yield* emit({
            _tag: "RunSettled",
            outcome: {
              _tag: "Failed",
              errorText: `[stub:${profile.backend}] task failed as requested by FAIL: prefix`,
            },
          });
          return;
        }

        const finalText =
          `[stub:${profile.backend}] completed: ${firstLine(userText).slice(0, 200)}\n\n` +
          `This is a stubbed ${profile.backend} subagent turn ${turn + 1}. ` +
          `The real backend integration will replace this scripted output.` +
          (teamleadReply ? ` Teamlead replied: ${teamleadReply}` : "");
        for (const delta of chunked(finalText, 24)) {
          yield* emit({ _tag: "AssistantDelta", kind: "text", delta });
          yield* pause;
        }
        yield* emit({
          _tag: "AssistantMessage",
          parts: [{ type: "text", text: finalText }],
        });
        yield* emit({
          _tag: "UsageChanged",
          tokens: Math.min(profile.contextWindow, 2400 * (turn + 1) + 900),
          contextWindow: profile.contextWindow,
        });
        yield* emit({
          _tag: "RunSettled",
          outcome: { _tag: "Completed", finalText },
        });
      });

    const queuedView = (): ReadonlyArray<QueuedMessage> =>
      state.pending.map(({ text }) => ({ text, kind: "steer" as const }));

    // Driver: one turn at a time, in submission order. Turns run as child
    // fibers so interrupt() stops the turn without killing the driver.
    const driver = Effect.gen(function* () {
      while (true) {
        const message = yield* Queue.take(inbox);
        state.dispatching = true;
        state.pending.shift();
        yield* emit({ _tag: "QueueChanged", queued: queuedView() });
        yield* emit({
          _tag: "UserMessage",
          text: message.text,
          source: message.source,
        });
        const turn = state.turnCount++;
        const fiber = yield* Effect.forkChild(
          runTurn(message.text, turn).pipe(
            Effect.onInterrupt(() =>
              emit({
                _tag: "RunSettled",
                outcome: { _tag: "Interrupted" },
              }).pipe(Effect.ignore),
            ),
          ),
        );
        yield* Ref.set(activeTurn, fiber);
        state.dispatching = false;
        yield* Fiber.await(fiber);
        yield* Ref.set(activeTurn, undefined);
      }
    });
    yield* Effect.forkScoped(driver.pipe(Effect.ignore));

    yield* Effect.addFinalizer(() =>
      Effect.gen(function* () {
        state.closed = true;
        yield* Queue.end(inbox).pipe(Effect.ignore);
        yield* Queue.end(events).pipe(Effect.ignore);
      }),
    );

    const submit = (
      text: string,
      source: "initial" | SubagentInputSource,
    ) =>
      Effect.gen(function* () {
        if (state.closed) {
          return yield* new SendError({
            message: "Subagent session is closed.",
          });
        }
        const message = { text, source } as const;
        state.pending.push(message);
        const busy = (yield* Ref.get(activeTurn)) !== undefined;
        if (busy) {
          // Show the queued steer line until the driver picks it up.
          yield* emit({ _tag: "QueueChanged", queued: queuedView() });
        }
        yield* Queue.offer(inbox, message);
      });

    // Announce metadata, then kick off the initial run.
    yield* Effect.try(() => fs.mkdirSync(STUB_DIR, { recursive: true })).pipe(
      Effect.ignore, // The fake session file directory is best-effort.
    );
    yield* emit({ _tag: "MetaChanged", meta: state.meta });
    // The session cannot be closed yet, so the initial submit cannot fail.
    yield* submit(task.prompt, "initial").pipe(Effect.orDie);

    return {
      meta: Effect.sync(() => state.meta),
      events: Stream.fromQueue(events),
      send: (text, source) => submit(text, source),
      reply: (requestId, text) =>
        Effect.suspend((): Effect.Effect<void, ReplyError> => {
          const pending = pendingReplies.get(requestId);
          if (!pending) {
            return new ReplyError({
              message: `Question "${requestId}" is no longer pending.`,
            });
          }
          const reply = text;
          if (!reply.trim()) {
            return new ReplyError({ message: "reply must not be empty." });
          }
          pendingReplies.delete(requestId);
          return emit({
            _tag: "QuestionClosed",
            requestId,
            messageId: `child-msg-${++communicationCounter}`,
            outcome: "replied",
            reply,
            createdAt: Date.now(),
          }).pipe(
            Effect.tap(() => Effect.sync(() => pending.resume(Effect.succeed(reply)))),
            Effect.asVoid,
          );
        }),
      interrupt: Effect.gen(function* () {
        // Drop queued prompts so interrupting cannot immediately start
        // another turn, then stop the active turn. A prompt may be mid-flight
        // between the driver dequeuing it and registering its fiber, so wait
        // that window out instead of silently missing the turn.
        const cleared = yield* Queue.clear(inbox).pipe(
          Effect.orElseSucceed(() => []),
        );
        state.pending = [];
        yield* emit({ _tag: "QueueChanged", queued: [] });
        while (true) {
          const fiber = yield* Ref.get(activeTurn);
          if (fiber) {
            yield* Fiber.interrupt(fiber);
            return;
          }
          if (!state.dispatching) {
            // No turn ever started. If we cancelled queued prompts, the run
            // still needs a terminal event or it would look running forever.
            if (cleared.length > 0) {
              yield* emit({
                _tag: "RunSettled",
                outcome: { _tag: "Interrupted" },
              });
            }
            return;
          }
          yield* Effect.sleep(Duration.millis(5));
        }
      }),
    } satisfies SubagentSession;
  });
