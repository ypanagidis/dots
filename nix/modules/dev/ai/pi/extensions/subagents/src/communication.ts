import { randomUUID } from "node:crypto";
import type { SubagentCommunication } from "./domain.ts";

export type { SubagentCommunication } from "./domain.ts";

/** The protocol limit is measured as UTF-8 bytes, not JavaScript code units. */
export const MAX_COMMUNICATION_TEXT_BYTES = 16 * 1024;
export const DEFAULT_MAX_PENDING_QUESTIONS = 64;
export const DEFAULT_SETTLED_REQUEST_HISTORY = 128;

export type CommunicationKind =
  | "update"
  | "question"
  | "reply"
  | "resolution";

export type QuestionSettlement =
  | "answered"
  | "timed-out"
  | "canceled"
  | "closed";

export type RequestState = "pending" | QuestionSettlement | "unknown";

export type CommunicationErrorCode =
  | "blank-text"
  | "text-too-large"
  | "invalid-timeout"
  | "too-many-pending"
  | "unknown-request"
  | "already-answered"
  | "timed-out"
  | "canceled"
  | "closed"
  | "id-collision";

export class CommunicationError extends Error {
  readonly code: CommunicationErrorCode;

  constructor(code: CommunicationErrorCode, message: string) {
    super(message);
    this.name = "CommunicationError";
    this.code = code;
  }
}

export interface CommunicationIdFactory {
  nextMessageId(): string;
  nextRequestId(): string;
}

/**
 * Session-local opaque IDs. A random namespace prevents cross-session clashes;
 * monotonic counters guarantee uniqueness without retaining every prior ID.
 * Callers should never parse IDs.
 */
export function createCommunicationIdFactory(
  namespaceSource: () => string = randomUUID,
): CommunicationIdFactory {
  const namespace = namespaceSource();
  if (typeof namespace !== "string" || namespace.trim().length === 0) {
    throw new CommunicationError(
      "id-collision",
      "Unable to allocate communication IDs: the session namespace is blank",
    );
  }
  let messageCounter = 0;
  let requestCounter = 0;

  const next = (kind: "msg" | "req") => {
    const counter = kind === "msg" ? messageCounter : requestCounter;
    if (counter >= Number.MAX_SAFE_INTEGER) {
      throw new CommunicationError(
        "id-collision",
        `Unable to allocate another ${kind === "msg" ? "message" : "request"} ID`,
      );
    }
    if (kind === "msg") messageCounter += 1;
    else requestCounter += 1;
    const serial = kind === "msg" ? messageCounter : requestCounter;
    return `${kind}-${namespace}-${serial}`;
  };

  return {
    nextMessageId: () => next("msg"),
    nextRequestId: () => next("req"),
  };
}

const utf8 = new TextEncoder();

/** Returns the original text unchanged after validating protocol bounds. */
export function validateCommunicationText(
  text: string,
  maxBytes = MAX_COMMUNICATION_TEXT_BYTES,
): string {
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0) {
    throw new RangeError("Communication text limit must be a positive integer");
  }
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new CommunicationError(
      "blank-text",
      "Communication text must not be blank",
    );
  }
  const size = utf8.encode(text).byteLength;
  if (size > maxBytes) {
    throw new CommunicationError(
      "text-too-large",
      `Communication text is ${size} bytes; the limit is ${maxBytes} bytes`,
    );
  }
  return text;
}

/** Build a bounded asynchronous update using the same session ID source. */
export function createUpdateCommunication(
  text: string,
  ids: CommunicationIdFactory,
  options: {
    readonly now?: () => number;
    readonly maxBytes?: number;
  } = {},
): SubagentCommunication & { readonly kind: "update" } {
  const validated = validateCommunicationText(
    text,
    options.maxBytes ?? MAX_COMMUNICATION_TEXT_BYTES,
  );
  return Object.freeze({
    messageId: ids.nextMessageId(),
    kind: "update" as const,
    text: validated,
    createdAt: (options.now ?? Date.now)(),
  });
}

export function appendBoundedCommunication(
  history: ReadonlyArray<SubagentCommunication>,
  item: SubagentCommunication,
  limit: number,
): ReadonlyArray<SubagentCommunication> {
  if (!Number.isSafeInteger(limit) || limit < 0) {
    throw new RangeError("Communication history limit must be a non-negative integer");
  }
  if (limit === 0) return [];
  const retained = limit === 1 ? [] : history.slice(-(limit - 1));
  return [...retained, item];
}

export interface PendingQuestion {
  readonly communication: SubagentCommunication & {
    readonly kind: "question";
    readonly requestId: string;
  };
  /** Resolves to the exact reply body; rejects on timeout, abort, or close. */
  readonly result: Promise<string>;
}

export interface CommunicationScheduler {
  schedule(callback: () => void, delayMs: number): unknown;
  cancel(handle: unknown): void;
}

const systemScheduler: CommunicationScheduler = {
  schedule(callback, delayMs) {
    const handle = setTimeout(callback, delayMs);
    // A forgotten question should not by itself keep a Node process alive.
    handle.unref?.();
    return handle;
  },
  cancel(handle) {
    clearTimeout(handle as ReturnType<typeof setTimeout>);
  },
};

interface PendingEntry {
  readonly question: PendingQuestion["communication"];
  readonly resolve: (text: string) => void;
  readonly reject: (error: CommunicationError) => void;
  readonly signal?: AbortSignal;
  onAbort?: () => void;
  timer?: unknown;
}

export interface PendingQuestionRegistryOptions {
  readonly timeoutMs?: number;
  readonly maxTextBytes?: number;
  readonly maxPending?: number;
  readonly settledHistoryLimit?: number;
  readonly ids?: CommunicationIdFactory;
  readonly now?: () => number;
  /** Test/integration clock; omit to use setTimeout. */
  readonly scheduler?: CommunicationScheduler;
  /** Synchronous lifecycle hook used by the backend event bridge. */
  readonly onSettled?: (event: {
    readonly requestId: string;
    readonly state: QuestionSettlement;
    readonly reply?: SubagentCommunication & {
      readonly kind: "reply";
      readonly requestId: string;
    };
  }) => void;
}

export interface AskOptions {
  readonly signal?: AbortSignal;
}

export interface PendingQuestionRegistry {
  ask(question: string, options?: AskOptions): PendingQuestion;
  /** Resolves a pending ask and returns the reply event for publication. */
  reply(requestId: string, message: string): SubagentCommunication & {
    readonly kind: "reply";
    readonly requestId: string;
  };
  /** First call wins. Returns false for an unknown or already-settled request. */
  cancel(requestId: string, reason?: string): boolean;
  /** Rejects every pending ask and prevents all future asks/replies. */
  close(reason?: string): void;
  state(requestId: string): RequestState;
  pending(): ReadonlyArray<PendingQuestion["communication"]>;
  readonly size: number;
  readonly isClosed: boolean;
}

export function createPendingQuestionRegistry(
  options: PendingQuestionRegistryOptions = {},
): PendingQuestionRegistry {
  const timeoutMs = options.timeoutMs ?? 10 * 60 * 1_000;
  const maxTextBytes = options.maxTextBytes ?? MAX_COMMUNICATION_TEXT_BYTES;
  const maxPending = options.maxPending ?? DEFAULT_MAX_PENDING_QUESTIONS;
  const settledHistoryLimit =
    options.settledHistoryLimit ?? DEFAULT_SETTLED_REQUEST_HISTORY;
  const ids = options.ids ?? createCommunicationIdFactory();
  const now = options.now ?? Date.now;
  const scheduler = options.scheduler ?? systemScheduler;

  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new CommunicationError(
      "invalid-timeout",
      "Question timeout must be a positive finite number",
    );
  }
  if (!Number.isSafeInteger(maxPending) || maxPending <= 0) {
    throw new RangeError("Maximum pending questions must be a positive integer");
  }
  if (!Number.isSafeInteger(settledHistoryLimit) || settledHistoryLimit < 0) {
    throw new RangeError("Settled request history limit must be non-negative");
  }

  const entries = new Map<string, PendingEntry>();
  const settled = new Map<string, QuestionSettlement>();
  let closed = false;

  const remember = (requestId: string, state: QuestionSettlement) => {
    if (settledHistoryLimit === 0) return;
    settled.delete(requestId);
    settled.set(requestId, state);
    while (settled.size > settledHistoryLimit) {
      const oldest = settled.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      settled.delete(oldest);
    }
  };

  const detach = (entry: PendingEntry) => {
    if (entry.timer !== undefined) scheduler.cancel(entry.timer);
    if (entry.signal && entry.onAbort) {
      entry.signal.removeEventListener("abort", entry.onAbort);
    }
  };

  const rejectPending = (
    requestId: string,
    state: Exclude<QuestionSettlement, "answered">,
    error: CommunicationError,
  ) => {
    const entry = entries.get(requestId);
    if (!entry) return false;
    // Delete before invoking user promise machinery: settlement is atomic and
    // any re-entrant reply observes the terminal tombstone.
    entries.delete(requestId);
    remember(requestId, state);
    detach(entry);
    options.onSettled?.({ requestId, state });
    entry.reject(error);
    return true;
  };

  const errorForReply = (requestId: string): CommunicationError => {
    if (closed) {
      return new CommunicationError(
        "closed",
        `Cannot reply to ${requestId}: the communication channel is closed`,
      );
    }
    const state = settled.get(requestId);
    if (state === "answered") {
      return new CommunicationError(
        "already-answered",
        `Request ${requestId} was already answered; replies are accepted exactly once`,
      );
    }
    if (state === "timed-out") {
      return new CommunicationError(
        "timed-out",
        `Request ${requestId} timed out and can no longer be answered`,
      );
    }
    if (state === "canceled") {
      return new CommunicationError(
        "canceled",
        `Request ${requestId} was canceled and can no longer be answered`,
      );
    }
    if (state === "closed") {
      return new CommunicationError(
        "closed",
        `Request ${requestId} was closed and can no longer be answered`,
      );
    }
    return new CommunicationError(
      "unknown-request",
      `No pending question matches request ID ${requestId}`,
    );
  };

  const api: PendingQuestionRegistry = {
    ask(question, askOptions = {}) {
      if (closed) {
        throw new CommunicationError(
          "closed",
          "Cannot ask a question: the communication channel is closed",
        );
      }
      const text = validateCommunicationText(question, maxTextBytes);
      if (entries.size >= maxPending) {
        throw new CommunicationError(
          "too-many-pending",
          `Cannot ask another question: ${maxPending} are already pending`,
        );
      }

      const requestId = ids.nextRequestId();
      const communication = Object.freeze({
        messageId: ids.nextMessageId(),
        requestId,
        kind: "question" as const,
        text,
        createdAt: now(),
      });
      let resolve!: (text: string) => void;
      let reject!: (error: CommunicationError) => void;
      const result = new Promise<string>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      const entry: PendingEntry = {
        question: communication,
        resolve,
        reject,
        signal: askOptions.signal,
      };
      entries.set(requestId, entry);

      if (askOptions.signal) {
        entry.onAbort = () => {
          rejectPending(
            requestId,
            "canceled",
            new CommunicationError(
              "canceled",
              `Request ${requestId} was canceled`,
            ),
          );
        };
        askOptions.signal.addEventListener("abort", entry.onAbort, {
          once: true,
        });
        if (askOptions.signal.aborted) entry.onAbort();
      }

      if (entries.has(requestId)) {
        entry.timer = scheduler.schedule(() => {
          rejectPending(
            requestId,
            "timed-out",
            new CommunicationError(
              "timed-out",
              `Request ${requestId} timed out after ${timeoutMs}ms`,
            ),
          );
        }, timeoutMs);
      }

      return { communication, result };
    },

    reply(requestId, message) {
      const entry = entries.get(requestId);
      if (!entry) throw errorForReply(requestId);
      const text = validateCommunicationText(message, maxTextBytes);
      // Build the event before mutating lifecycle state. Even an injected ID
      // source failure must leave the question answerable.
      const communication = Object.freeze({
        messageId: ids.nextMessageId(),
        requestId,
        kind: "reply" as const,
        text,
        createdAt: now(),
      });

      entries.delete(requestId);
      remember(requestId, "answered");
      detach(entry);
      options.onSettled?.({
        requestId,
        state: "answered",
        reply: communication,
      });
      entry.resolve(text);
      return communication;
    },

    cancel(requestId, reason = "Question was canceled") {
      return rejectPending(
        requestId,
        "canceled",
        new CommunicationError("canceled", `${reason} (${requestId})`),
      );
    },

    close(reason = "Communication channel closed") {
      if (closed) return;
      closed = true;
      for (const requestId of [...entries.keys()]) {
        rejectPending(
          requestId,
          "closed",
          new CommunicationError("closed", `${reason} (${requestId})`),
        );
      }
    },

    state(requestId) {
      if (entries.has(requestId)) return "pending";
      return settled.get(requestId) ?? "unknown";
    },

    pending() {
      return [...entries.values()].map((entry) => entry.question);
    },

    get size() {
      return entries.size;
    },

    get isClosed() {
      return closed;
    },
  };

  return api;
}
