/** All model-facing strings for the subagents tools. */

/** Describes subagent_spawn, including task-based model selection and concurrency. */
export const SUBAGENT_SPAWN_TOOL_DESCRIPTION =
  "Spawn a background subagent: a fully autonomous, headless in-process pi session with its own context window and normal tools. Set model to openai-codex/gpt-5.6-sol for all coding tasks, or openai-codex/gpt-6-astra for everything else. Fire-and-forget: this returns immediately with an id, and every completed run sends its own final-message callback. Children cannot orchestrate workflows or ask the user directly. By default they cannot spawn subagents; allowed_subagents_depth grants a bounded number of managed descendant generations, and each nested spawn must decrease that allowance. Children can exchange targeted messages with their teamlead. They cannot see this conversation, so the prompt must be self-contained. Ask the child to end with a self-contained final response covering findings, changed files, verification, and blockers; that is the message the teamlead receives. Only use trusted working directories. Max 4 subagents can be running at once per coordinator session.";

/** Adds background subagent delegation to the parent model's available-tools prompt. */
export const SUBAGENT_SPAWN_PROMPT_SNIPPET =
  "Spawn a background pi subagent using GPT-5.6 Sol for coding or GPT-6 Astra for everything else";

/** Guides the parent model to delegate standalone tasks and avoid unnecessary blocking waits. */
export const SUBAGENT_SPAWN_PROMPT_GUIDELINES = [
  "Use subagent_spawn to delegate self-contained tasks that can run in the background; give it a complete, standalone prompt and require a self-contained final response with findings, changed files, verification, and blockers because that final response is the completion callback.",
  "For subagent_spawn, explicitly set model to openai-codex/gpt-5.6-sol for all coding tasks, including implementation, debugging, tests, refactoring, and code review. Use openai-codex/gpt-6-astra for everything else, including research, planning, analysis, and writing. Both run as in-process pi sessions.",
  "After subagent_spawn, keep doing useful independent work. subagent_wait is asynchronous: call it only when you want to declare which results you are awaiting, never poll or invoke it again for the same runs, and then either continue useful work or give the user a concise delegation update and end the turn so callbacks can arrive.",
  "Use subagent_send for unsolicited guidance and subagent_reply with the exact request_id when a child asks a blocking teamlead question.",
  "Set allowed_subagents_depth only when the child needs to delegate further: 0 (the default) disables child spawning, 1 permits one leaf generation, and every nested spawn must request at least one less than its parent session's remaining allowance.",
];

/** Model-facing schema descriptions for subagent_spawn task and execution options. */
export const SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS = {
  prompt:
    "Task prompt for the subagent. Must be self-contained: include all needed context, file paths, and require a sensible final response with findings, changed files, verification, and blockers.",
  name: "Short human-readable name for this subagent, shown in listings and the UI",
  model:
    "Use openai-codex/gpt-5.6-sol for all coding tasks; use openai-codex/gpt-6-astra for everything else. Defaults to GPT-5.6 Sol for older calls that omit model.",
  workingDir:
    "Trusted working directory for the autonomous child (default: current working directory)",
  reasoningEffort:
    "Reasoning effort for the pi session. Omit to inherit the parent thinking level.",
  allowedSubagentsDepth:
    "Number of managed descendant generations the child may create (default 0). A nested child must request at least one less than its current session allowance.",
};

/** Builds the subagent_spawn result that tells the parent model how to continue or inspect the child. */
export function buildSubagentSpawnResult(options: {
  id: string;
  title: string;
  harness: string;
  modelLabel: string;
  cwd: string;
  allowedSubagentsDepth: number;
}) {
  return (
    `Spawned subagent ${options.id} "${options.title}" (${options.harness}: ${options.modelLabel}, ${options.cwd}).\n` +
    `It runs in the background with allowed_subagents_depth=${options.allowedSubagentsDepth}, and its final response will arrive as an individual callback. ` +
    `Use subagent_wait(ids: ["${options.id}"]) to register an asynchronous wait, subagent_send to message it, subagent_cancel to stop it, subagent_check to peek, and subagent_list to see all.`
  );
}

/** Describes a nonblocking declaration that selected results are awaited. */
export const SUBAGENT_WAIT_TOOL_DESCRIPTION =
  "Register interest in one or more subagents without blocking. This returns immediately; each subagent sends its own final-message callback when its current run settles. After calling, do not poll or invoke it again for the same runs: continue useful independent work, or give the user a concise delegation update and end the turn.";

/** Model-facing schema description for the subagent ids to await. */
export const SUBAGENT_WAIT_PARAMETER_DESCRIPTIONS = {
  ids: 'Subagent ids whose individual completion callbacks you are awaiting, e.g. ["sa-1", "sa-2"]',
};

export const SUBAGENT_SEND_TOOL_DESCRIPTION =
  "Send an asynchronous message to a subagent. A running child receives it at the next safe boundary; a settled child starts a new run in the same session. Returns after acceptance, not after the child processes it.";

export const SUBAGENT_SEND_PARAMETER_DESCRIPTIONS = {
  id: "Subagent id",
  message: "Message or guidance for the subagent (maximum 16 KiB)",
};

export const SUBAGENT_REPLY_TOOL_DESCRIPTION =
  "Resolve exactly one blocking teamlead_ask from a subagent. Use the exact subagent id and request_id from its question message. This returns after the waiting child tool receives the reply.";

export const SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS = {
  id: "Subagent id that asked the question",
  requestId: "Exact request_id from the subagent question",
  message:
    "Reply message to return directly to the waiting child tool (maximum 16 KiB)",
};

export const TEAMLEAD_SEND_TOOL_DESCRIPTION =
  "Send a material asynchronous update to the teamlead. Use sparingly for important findings or blockers, not routine narration. This returns immediately; continue working after sending.";

export const TEAMLEAD_SEND_PARAMETER_DESCRIPTIONS = {
  message: "Important update or message for the teamlead",
};

export const TEAMLEAD_ASK_TOOL_DESCRIPTION =
  "Ask the teamlead a specific question whose reply is required to continue. This tool remains pending while it waits for the parent to answer with subagent_reply; use only when genuinely blocked.";

export const TEAMLEAD_ASK_PARAMETER_DESCRIPTIONS = {
  question: "Specific question requiring a teamlead reply",
};

/** Keeps task completion distinct from intermediate idle model turns. */
export const SUBAGENT_CHILD_LIFECYCLE_GUIDANCE = `
[Subagent lifecycle]
You are running as a managed background subagent. You may use callback-enabled
background-task tools for long operations and remain available for teamlead messages
while they run. A background job that is part of your task remains part of this managed
run: do not claim the overall task is complete until its callback arrives and you have
verified the result. Use teamlead_send for material interim updates. Your final
self-contained answer after all task-critical background work finishes marks completion.
[/Subagent lifecycle]`;

/** Describes aborting running subagents while retaining their partial transcripts. */
export const SUBAGENT_CANCEL_TOOL_DESCRIPTION =
  "Cancel one or more running subagents. This aborts their active work but preserves their partial session transcripts on disk.";

/** Model-facing schema description for the subagent ids to cancel. */
export const SUBAGENT_CANCEL_PARAMETER_DESCRIPTIONS = {
  ids: 'Subagent ids to cancel, e.g. ["sa-1", "sa-2"]',
};

/** Describes nonblocking inspection of a subagent without consuming its result. */
export const SUBAGENT_CHECK_TOOL_DESCRIPTION =
  "Peek at a subagent's status and recent activity without blocking. Does not consume its result.";

/** Model-facing schema description for the subagent id to inspect. */
export const SUBAGENT_CHECK_PARAMETER_DESCRIPTIONS = {
  id: "Subagent id",
};

/** Describes listing all tracked running and settled subagents. */
export const SUBAGENT_LIST_TOOL_DESCRIPTION =
  "List all subagents (running and finished) with their harness and status.";

/** Builds the child completion/failure wrapper injected into the parent model's context. */
export function buildSubagentResultMessage(options: {
  id: string;
  title: string;
  status: "running" | "done" | "error";
  errorText?: string;
  output: string;
}) {
  const verb = options.status === "error" ? "failed" : "finished";
  let text = `Subagent ${options.id} "${options.title}" ${verb}.`;
  if (options.errorText) text += `\nError: ${options.errorText}`;
  text += `\n\n${options.output}`;
  return text;
}
