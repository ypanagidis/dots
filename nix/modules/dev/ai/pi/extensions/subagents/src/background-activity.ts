const BACKGROUND_ID_PATTERN = /\bbg_[A-Za-z0-9_]+\b/g;
const SUBAGENT_COMPLETION_ID_PATTERN = /^sa-[1-9]\d*:run-[1-9]\d*$/;
const SUBAGENT_ACTIVITY_PREFIX = "subagent:";
const TERMINAL_STATUSES = new Set([
  "succeeded",
  "failed",
  "cancelled",
  "canceled",
  "timed-out",
  "timed_out",
  "stopped",
]);

function record(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function textContent(value: unknown): string {
  if (typeof value === "string") return value;
  const content = record(value)?.content;
  if (!Array.isArray(content)) return "";
  return content
    .flatMap((part) => {
      const item = record(part);
      return item?.type === "text" && typeof item.text === "string"
        ? [item.text]
        : [];
    })
    .join("\n");
}

function uniqueIds(text: string): string[] {
  return [
    ...new Set(
      (text.match(BACKGROUND_ID_PATTERN) ?? []).filter(
        (id) => id !== "bg_task" && !id.startsWith("bg_task_"),
      ),
    ),
  ];
}

function subagentActivityId(value: unknown): string | undefined {
  return typeof value === "string" && SUBAGENT_COMPLETION_ID_PATTERN.test(value)
    ? `${SUBAGENT_ACTIVITY_PREFIX}${value}`
    : undefined;
}

function startedSubagentIds(options: {
  toolName: string;
  result: unknown;
  isError: boolean;
}): string[] {
  if (options.isError) return [];
  const details = record(record(options.result)?.details);
  if (options.toolName === "subagent_spawn") {
    const id = subagentActivityId(details?.completionId);
    return id ? [id] : [];
  }
  if (
    options.toolName === "subagent_send" &&
    details?.startsNewRun === true
  ) {
    const id = subagentActivityId(details.completionId);
    return id ? [id] : [];
  }
  return [];
}

function isBackgroundStartTool(
  toolName: string,
  args: Record<string, unknown> | undefined,
): boolean {
  if (toolName === "bg_task_spawn" || toolName === "bg_task_watch") return true;
  if (toolName !== "bg_task") return false;
  return args?.action === "spawn" || args?.action === "watch";
}

/** IDs of callback-enabled nested jobs that should hold the child lifecycle open. */
export function startedBackgroundTaskIds(options: {
  toolName: string;
  args: unknown;
  result: unknown;
  isError: boolean;
}): string[] {
  const subagents = startedSubagentIds(options);
  if (subagents.length > 0) return subagents;
  const args = record(options.args);
  if (
    options.isError ||
    args?.callback === false ||
    !isBackgroundStartTool(options.toolName, args)
  ) {
    return [];
  }
  const text = textContent(options.result);
  if (!/(?:started|watching).{0,40}background|status:\s*running/i.test(text)) {
    return [];
  }
  return uniqueIds(text);
}

/** Terminal task IDs surfaced by callback custom messages or status/stop tools. */
export function completedBackgroundTaskIds(value: unknown): string[] {
  const item = record(value);
  const customType = item?.customType;
  const details = record(item?.details);

  if (customType === "subagent-result") {
    const id = subagentActivityId(details?.completionId);
    return id ? [id] : [];
  }

  const cancelled = Array.isArray(details?.results)
    ? details.results.flatMap((result) => {
        const item = record(result);
        if (item?.cancelled !== true) return [];
        const id = subagentActivityId(item.completionId);
        return id ? [id] : [];
      })
    : [];
  if (cancelled.length > 0) return [...new Set(cancelled)];

  const text = textContent(value) ||
    (typeof item?.content === "string" ? item.content : "");
  if (!text) return [];

  if (customType === "background-completion-batch") {
    const completed: string[] = [];
    for (const line of text.split("\n")) {
      const status = line.match(/\bstatus=([a-z_-]+)/i)?.[1]?.toLowerCase();
      if (!status || !TERMINAL_STATUSES.has(status)) continue;
      completed.push(...uniqueIds(line));
    }
    return [...new Set(completed)];
  }

  if (
    /\b(?:is|status:)\s*(?:succeeded|failed|cancelled|canceled|timed[-_ ]out|stopped)\b/i.test(
      text,
    )
  ) {
    return uniqueIds(text);
  }
  return [];
}

/** Session-local lifecycle tracker with completion-before-start race protection. */
export class BackgroundActivityTracker {
  private readonly pending = new Set<string>();
  private readonly completed = new Set<string>();

  get pendingCount(): number {
    return this.pending.size;
  }

  get pendingIds(): ReadonlyArray<string> {
    return [...this.pending];
  }

  recordStarted(options: {
    toolName: string;
    args: unknown;
    result: unknown;
    isError: boolean;
  }): void {
    for (const id of startedBackgroundTaskIds(options)) {
      if (!this.completed.has(id)) this.pending.add(id);
    }
  }

  reconcilePendingSubagents(ids: ReadonlyArray<string>): void {
    const desired = new Set(
      ids.flatMap((id) => {
        const activityId = subagentActivityId(id);
        return activityId ? [activityId] : [];
      }),
    );
    for (const id of this.pending) {
      if (id.startsWith(SUBAGENT_ACTIVITY_PREFIX) && !desired.has(id)) {
        this.pending.delete(id);
      }
    }
    for (const id of desired) {
      if (!this.completed.has(id)) this.pending.add(id);
    }
  }

  recordCompleted(value: unknown): void {
    for (const id of completedBackgroundTaskIds(value)) {
      this.pending.delete(id);
      this.completed.add(id);
    }
    while (this.completed.size > 256) {
      const oldest = this.completed.values().next().value;
      if (oldest === undefined) break;
      this.completed.delete(oldest);
    }
  }

  cancelPending(): void {
    for (const id of this.pending) this.completed.add(id);
    this.pending.clear();
  }

  clear(): void {
    this.pending.clear();
    this.completed.clear();
  }
}
