# Subagents — asynchronous delegation and messaging design

## Status

Production subagents are **Pi-only**. A model-origin child is an in-process Pi session
fixed to `openai-codex/gpt-5.6-sol`; the parent cannot select Claude Code, Codex CLI, or
a different model. The legacy backend adapters may remain in the source tree for
compatibility and tests, but they are not part of the production spawn surface.

Subagents are owned by the parent session. The parent persists a compact manifest
linking stable `sa-N`/`btw-N` ids to each child Pi JSONL. Reload, graceful quit, and
hard-crash recovery reopen children that were last checkpointed as running or suspended
and automatically continue them from their durable transcript. `/new` leaves old
children suspended; resuming that parent session continues them. Fork/clone and `/tree`
navigation deliberately establish a recovery boundary and do not inherit mutable child
session ownership. At most four children may be running at once.

Recovery is transcript continuation, not resurrection of an in-flight provider stream,
tool promise, or subprocess. Fresh Pi children remain idle until their parent manifest
link is durable. On reopen, unmatched tool calls receive explicit interrupted error
results. A clean final assistant tail settles without another model turn; only incomplete,
aborted, or background-held work receives a recovery turn that first inspects the
workspace and durable history before retrying, so side effects are not repeated blindly.
Running checkpoints also retain accepted-but-not-yet-delivered child messages. Terminal
checkpoints are keyed by public id plus run number and retain a bounded pending callback
until its parent message is durable, preventing a later run or a crash between
child settlement and callback delivery from losing the result. Public id counters
reserve every id seen in the parent history before accepting fresh spawns.

## Compact running-agent pane

In TUI mode, the teamlead's complete currently-running model-origin (`sa-*`) descendant
tree is rendered in a reactive widget below the prompt editor. Settled/cancelled nodes
and `btw-*` sessions remain available through `/subagents` but do not occupy the compact
pane. A settled ancestor is retained only when needed to connect a running descendant.

A compact teamlead root is followed by Unicode tree connectors and one row per visible
node. Every row contains its local id, spawn title, backend, model, context
occupancy/window, and newest thinking step. Public `sa-N` ids may repeat under different
coordinators; selection and routing use the child's stable native session id instead.
While the pane is focused, the selected row is bold with a full-width `selectedBg`
highlight. Latest thinking prefers the live reasoning stream, falls back to the newest
finalized non-redacted thinking part, reduces a multi-step reasoning block to its newest
paragraph/markdown step, and sanitizes/truncates it to one terminal-safe line.

The pane starts unfocused, so Up continues to browse prompt history. With an exactly
empty prompt, one physical Down press focuses the first/current row without moving it.
While focused, a reactive above-editor history pane pushes the teamlead transcript out
of the visible history region without overlaying Pi's editor, compact rows, status, usage,
or footer. The selected child's history is composed with Pi's exported
`UserMessageComponent`, `AssistantMessageComponent`, and `ToolExecutionComponent`, so
user boxes, Markdown, thinking, and tools match the normal transcript instead of using a
parallel renderer. Its header shows the complete local-id path (for example,
`sa-1 › sa-2`). Down advances through the flattened running tree; Up moves toward the
first node and, when already on the first, returns to the teamlead transcript. Escape also
returns, while PageUp/PageDown scrolls the replacement history. Left is deliberately
unclaimed because the background-task extension uses it. While
focused, normal typing/multiline editing stays in Pi's prompt editor and Enter sends the
text to the selected child through the manager's existing steer/restart path, then keeps
the child history active. Entering/leaving forces a full TUI redraw so the large history-pane shrink cannot leave the restored
teamlead transcript above the terminal viewport. While focused, only the normal prompt
editor border is recolored with the accent theme color, and the teamlead-specific
`Working...` row is hidden and restored on exit.

The implementation decorates the existing custom editor factory when present so earlier
editor extensions retain their behavior. The decorated editor carries a global-symbol
refresh hook, and in-session `/tree` rewinds preserve its controller/factory while the
manager registration is replaced; this prevents proxying editor extensions from forming
recursive `handleInput` chains. On reload/session replacement, the fallback editor is
rehydrated with the active branch's restored user prompts because Pi transfers editor
text, but not the default editor's private history.

One root-owned `SubagentTreeRegistry` is propagated to nested in-process Pi sessions by a
hidden inline bridge extension on each child resource loader. The bridge uses the child
loader's scoped event bus, avoiding assumptions about jiti module caching. Every
coordinator registers its manager under its native session id; projection recursively
joins child snapshot session ids to coordinator endpoints and routes takeover send/abort
to the owning manager. Registration is removed on session shutdown, tree replacement,
or scope disposal. The tree deliberately reflects currently tracked managers: after a
process restart, existing recovery semantics rehydrate running/suspended ownership but
not arbitrary historical settled descendants.

## Parent tools

### `subagent_spawn`

Spawning is fire-and-forget and returns an `sa-N` identifier immediately. A child cannot
see the parent conversation, run workflows, or ask the user directly, so its task prompt
must contain all necessary context. `allowed_subagents_depth` defaults to zero, preserving
the non-orchestrating child behavior. A positive value grants that child a bounded number
of managed descendant generations: `1` permits one leaf generation, and every nested
spawn must request at least one less than the current session's allowance. The allowance
is persisted in both the parent recovery checkpoint and an immutable, session-wide child
policy marker; resume requires them to agree, a missing positive policy is rejected, and
malformed or conflicting markers fail closed. Child extension `session_start` hooks are
delayed until after its manager-owned parent link is durable and its event pump is
installed, so recursive
recovery cannot start descendants in the pre-checkpoint gap. Each coordinator session
retains its own four-running-child cap, so an explicitly enabled tree can have
more than four total descendants across independent branches.

The prompt also tells the child to end with a self-contained final answer containing its
findings, changed files, verification, and blockers. That final answer—not an implicit
transcript summary—is what the teamlead receives. Nested `subagent_spawn` and settled-child
`subagent_send` calls count as callback-enabled background activity, keeping the enclosing
managed run open until the exact `sa-N:run-R` descendant callback or cancellation receipt
arrives. Settled-child messaging returns a manager-owned acceptance receipt rather than
predicting the restarted run in the tool layer, and returns only after both the guidance
message and the new run's lifecycle checkpoint are durable; it does not wait for the
restarted model run to finish. Live checkpoint-entry reconciliation and recovery both
seed these holds from durable descendant ownership, covering a crash or tool abort before
the spawning tool result reached the enclosing transcript.

### `subagent_wait`

Waiting is an asynchronous subscription/acknowledgement, not a blocking tool operation.
It validates and deduplicates the requested IDs, reports their current states and which
are still pending, and returns immediately. It never calls the manager's settlement
wait primitive and never consumes completion results.

Every child completion remains an **individual callback**. Results are delivered in
settlement order as `subagent-result` follow-ups, one message per child run; there is no
combined all-done callback. Repeated waits do not poll, duplicate, suppress, or consume
those callbacks. For a settled run, wait reports whether its callback is pending/queued
or has already been emitted.

The model-facing acknowledgement tells the teamlead not to poll or repeatedly call
wait. After waiting, it should continue useful independent work. If no work remains, it
should give the user a concise delegation update and end the turn so later individual
callbacks can resume the parent naturally. The wait result must not force turn
termination before that sensible interim response.

### `subagent_send`

`subagent_send({ id, message })` sends unsolicited guidance to a child. For a running
child, the message is queued for its next safe turn boundary. For a settled child, it
starts another turn in the same child session, subject to the four-running-child cap.
The operation resolves when the backend accepts the message, not when the child has
processed it.

Unknown or hidden IDs, blank or oversized messages, shutdown/pruning, and restart
concurrency failures are reported explicitly. Prompt preflight is treated as an active
start: concurrent sends share one restart slot and queue into that start rather than
launching overlapping `prompt()` calls; cancellation wins over a late native start.

### `subagent_reply`

`subagent_reply({ id, request_id, message })` resolves exactly one outstanding
`teamlead_ask` from that child. The reply is correlated out-of-band and becomes the
result of the pending child tool call; it is never implemented with child steering,
which cannot be delivered while that tool batch is waiting. Unknown, mismatched,
stale, timed-out, canceled, and already-answered requests produce actionable errors.

`subagent_check`, `subagent_list`, and cancellation remain coordinator-local model tools.
The `/subagents` dashboard instead projects the complete currently tracked descendant
tree, including settled nodes, with connectors and qualified selection. Any descendant
can be opened directly; takeover guidance and aborts route to that node's owning manager.
Opening the dashboard or takeover still consumes no model-facing message. Depth-policy
tests cover the default-zero behavior, strict
decrement, malformed-policy fail-closed handling, tool exposure, recovery persistence,
and nested callback/cancellation lifecycle holds.

## Child-to-teamlead communication

Normal model-origin Pi children receive two custom tools at session creation. By-the-way
children do not receive them.

- `teamlead_send({ message })` asynchronously publishes a material progress update to
  the parent and returns immediately. The child is told to continue working and to use
  updates sparingly rather than narrating routine activity.
- `teamlead_ask({ question })` publishes a correlated question and leaves only that
  child tool call pending. It resumes with the exact reply supplied through
  `subagent_reply`. Pending asks have a fixed ten-minute safety timeout and are rejected
  on child cancellation or session shutdown. Timeout/cancellation publishes a
  correlated resolution message so the parent does not keep treating it as answerable.

Updates and questions use individual `subagent-message` parent messages delivered as a
**steer** with turn triggering. This lets a busy teamlead see them at its next safe turn
boundary. Question messages include the stable `request_id` and exact
`subagent_reply({ id, request_id, message })` shape. Final child results continue to use
**follow-up** delivery so they do not derail an active parent run.

## Run-safe delivery

A child session can be restarted, so identity is per run rather than only per public
`sa-N` ID. Snapshots carry a manager-owned run number, and a completion key such as
`sa-2:run-3` identifies one immutable settlement. Deferred result delivery is keyed by
that completion identity, preserving successive completions from the same child while
still delivering each exactly once. Terminal snapshots are copied before deferral.

Completion messages retain the existing 24 KiB truncation and child-session-file
pointer. Cancellation suppression remains explicit, run-scoped, and recorded as a
delivery tombstone; asynchronous wait neither suppresses nor resurrects those results.

Communication records are bounded and ordered per child. Snapshot state distinguishes
lifecycle (`running | done | error`) from outstanding questions, so a child blocked in
`teamlead_ask` is still running. Guidance delivered through `subagent_send` is tagged as
teamlead communication rather than rendered as an ordinary user prompt. Takeover and
running-history views render every inter-agent message as a directional communication
(for example, `↑ question to teamlead` and `↓ guidance from teamlead`). Communication
tool rows identify their destination, and expanded tool output includes the full sent
message. Opening the UI neither consumes messages nor answers questions.

## Lifecycle and delivery invariants

- No model-facing wait tool call stays open for child settlement.
- Completion callbacks are individual, ordered, run-safe, and scheduled once per in-memory run.
- Interim updates steer the parent; terminal results follow up the parent.
- Reply/timeout/cancel races are first-wins, with atomic pending-request removal.
- Late replies never start a new child run accidentally.
- Message and question bodies and retained communication history are bounded.
- On shutdown, checkpoint running children as suspended before stopping sends/replies,
  clearing deferred parent communication, rejecting pending child questions, and
  disposing child scopes/runtime resources.
- Reload and reopening the same parent branch preserve child ids, run numbers, creation
  times, transcript history, and child-session paths, then auto-continue recoverable runs.
- Recovery is at-least-once continuation from finalized JSONL messages; in-flight native
  work is not recoverable and must be inspected/reconciled by the recovery turn.
- Historical background-task start/results and completion messages are replayed through
  the lifecycle tracker before deciding whether a restored child is already complete.
- Children with a zero descendant allowance cannot call orchestration tools. A positive
  allowance exposes the managed `subagent_*` tools, but every nested spawn is runtime-
  checked to decrease the remaining allowance; workflows and direct user prompts remain
  excluded at every depth.
- Callback-enabled child background tasks are part of the managed logical run. The Pi
  backend tracks task IDs from spawn/watch results, withholds `RunSettled` while any are
  pending, and releases the hold when completion-batch/status messages report terminal
  state. Intermediate turns (including replies to teamlead guidance) may settle without
  hiding the child or freeing its concurrency slot; the callback continuation produces
  the one final settlement after all tracked work completes.

## Verification focus

Tests should establish that wait returns without depending on child timers or
settlement; unknown/hidden IDs still fail; IDs are deduplicated; repeated waits neither
consume nor duplicate callbacks; and two runs of one child retain two completion
messages. Messaging tests cover update delivery, stable request IDs, exact replies,
wrong-pair/duplicate/timeout/cancel/shutdown failures, send-to-running versus
restart-settled behavior, ordering, and by-the-way isolation. Prompt tests lock in the
nonblocking/no-poll/interim-response workflow and the child's self-contained final-answer
contract.
