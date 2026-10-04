# Plan: asynchronous subagent waiting and teamlead messaging

## Decisions confirmed

- `subagent_wait` becomes **nonblocking**.
- Completions remain **individual**: every selected subagent delivers its own final message; there is no grouped all-done callback.
- Messaging supports both asynchronous updates and explicit request/reply.
- Interim subagent messages reach a busy teamlead as a **steer** at the next safe parent turn boundary.
- Completion results remain follow-ups so they do not derail an active parent run.

## Important constraint

Pi has no deferred tool-result protocol: a tool call is active until `execute()` resolves, and `onUpdate` cannot finish it later. Therefore `subagent_wait` must return immediately and use a later `pi.sendMessage()` callback. The extension already has the correct callback mechanism for individual completions, so the redesign should reuse and harden it rather than invent a second result path.

## Model-facing API

### Teamlead tools

1. Keep `subagent_wait({ ids })`, but change it to:
   - validate/deduplicate IDs;
   - return immediately with each current status and the running IDs;
   - never call `manager.waitFor()` and never consume completion results;
   - state that each subagent will deliver its own final callback;
   - tell the model not to poll or call wait repeatedly.

   Example result:

   ```text
   Waiting asynchronously for sa-1, sa-2.
   Pending: sa-1, sa-2.
   Each subagent will deliver its final message separately. Continue useful work;
   if none remains, give the user a concise delegation update and end this turn.
   ```

   Do **not** return `terminate: true`: the model needs one follow-up response in which it can give the user a sensible interim message.

2. Add `subagent_send({ id, message })`:
   - running child: queue the message at the next safe child boundary;
   - settled child: start a new turn in the same child session;
   - resolve once the backend accepts the message, not once it is processed;
   - reject unknown/hidden IDs, blank messages, oversize messages, shutdown, pruning, and restart concurrency-limit failures.

3. Add `subagent_reply({ id, request_id, message })`:
   - resolve exactly one outstanding `teamlead_ask` call out-of-band;
   - do not route the reply through `session.steer()` (that would deadlock while the child tool is waiting);
   - reject stale, timed-out, already-answered, mismatched, or unknown request IDs with an actionable error.

### Child-only tools

Inject these with `createAgentSession({ customTools })` for normal model-origin Pi children only:

1. `teamlead_send({ message })`
   - enqueue a material update for the parent and return immediately;
   - tell the child that delivery is asynchronous and that it should continue working;
   - use sparingly, not for routine narration.

2. `teamlead_ask({ question })`
   - emit a correlated question with a stable `request_id`;
   - keep only this child tool call pending until `subagent_reply` arrives;
   - return the reply as the child tool result so the same child turn can continue;
   - abort cleanly on child cancellation/session shutdown and use a fixed safety timeout (proposed: 10 minutes) so one unanswered question cannot occupy a concurrency slot forever.

## Implementation phases

### 1. Make completion delivery run-safe

Messaging can restart settled children, so result delivery must distinguish runs rather than keying only by `sa-N`.

- Add a manager-owned `run` number to `SubagentSnapshot` and include it in completion/message details.
- Normalize `RunStarted` so one logical run increments exactly once (the Pi backend currently has both an optimistic start event and the SDK lifecycle event).
- Introduce an immutable completion identity such as `sa-2:run-3`.
- Change `src/result-delivery.ts` to key deferred results by completion identity, preserving two completions from successive runs instead of overwriting by subagent ID.
- Continue copying terminal snapshots before deferral.
- Preserve individual `subagent-result` custom messages and the existing 24 KiB truncation/session-file pointer.
- Keep cancellation suppression explicit, but rename the manager’s current `consumed`/`waitInterest` terminology so it no longer implies a blocking wait.

### 2. Replace blocking `subagent_wait`

In `index.ts`:

- remove the `runTool(manager.waitFor(...))`, `onUpdate`, large combined-output builder, and `resultDelivery.consume(ids)` path;
- synchronously validate IDs and inspect the current snapshots;
- return an acknowledgement/status result immediately;
- leave deferred and future completion events untouched so each run is delivered once by the normal callback path;
- for already-settled runs, report whether their callback is pending/queued or was already emitted; do not duplicate it.

In `src/manager.ts`:

- remove the public `waitFor` operation if no internal caller remains;
- retain the one-shot change primitive for cancellation;
- replace `waitInterest` with narrowly named cancellation/suppression state used only where a tool intentionally returns the terminal status itself.

In `src/prompt.ts`:

- replace all “block until” wording in the wait description, spawn result, and guidelines;
- explicitly instruct the teamlead: after async wait, continue useful independent work; otherwise send a concise interim user-facing message and end the turn; do not poll;
- strengthen spawn guidance so every child ends with a self-contained final response containing findings, changed files, verification, and blockers—the final response is what the teamlead receives.

No separate subagent skill file exists in this tree; the relevant model behavior currently comes from `promptSnippet`/`promptGuidelines`. If deployment also supplies an external skill, mirror the same guidance there.

### 3. Add the communication protocol

#### Domain and backend contract

In `src/domain.ts`, add bounded communication types/events, for example:

```ts
type SubagentCommunication = {
  messageId: string;
  requestId?: string;
  kind: "update" | "question" | "reply";
  text: string;
  createdAt: number;
};
```

Add normalized events for:

- child update/question sent to the lead;
- question resolved, timed out, or canceled;
- teamlead reply recorded.

Expose pending questions in snapshots separately from lifecycle status; a child remains `running` while blocked in `teamlead_ask`.

In `src/backend.ts`:

- keep ordinary `send(text)` for steering/restarting;
- add a correlated `reply(requestId, text)` operation or an explicit request/reply capability;
- unsupported legacy backends must fail clearly rather than pretending to accept replies.

#### Pi child bridge

In `src/backends/pi.ts`:

- create the normalized event queue before `createAgentSession()` so custom child tools can publish immediately;
- define `teamlead_send` and `teamlead_ask` with Pi’s exported `defineTool()` and pass them as `customTools`;
- maintain a session-scoped map of pending request deferreds;
- generate request IDs inside the child channel; routing remains unambiguous because the parent tool also requires the public subagent ID;
- make reply/timeout/abort races first-wins and remove the pending map entry atomically;
- reject all pending asks during finalization;
- expose neither child tool to `btw` sessions;
- deny all `subagent_*` orchestration tools by default; expose them only when a durable, strictly decreasing `allowed_subagents_depth` policy explicitly permits managed descendants, while keeping routing checks intact.

Use a custom tool result for replies rather than child steering: while `teamlead_ask` is running, steering is not delivered until the child’s current tool batch finishes and would deadlock.

#### Manager routing

In `src/manager.ts`:

- fold communication events into bounded snapshot state;
- add `message(id, text)` and `reply(id, requestId, text)` effects with typed errors;
- add a read-model callback such as `setOnMessage(...)` after state has been folded;
- preserve per-subagent ordering;
- keep the TUI takeover’s existing auto-restart behavior, but stop discarding send errors silently where practical.

#### Parent delivery

In `index.ts`:

- wire `setOnMessage` when the manager is created;
- deliver child updates/questions with `pi.sendMessage({ customType: "subagent-message", ... }, { deliverAs: "steer", triggerTurn: true })`;
- include the exact `subagent_reply` call shape and `request_id` in question content;
- guard against session shutdown before injecting parent messages;
- register a compact renderer distinguishing update, question, and reply state;
- keep final `subagent-result` messages on `followUp` delivery and preserve one callback per completed subagent run.

### 4. Update status and takeover UI

- `subagent_check`: include `run`, queued teamlead messages, and outstanding request IDs/questions.
- `subagent_list`: add a compact “awaiting reply” indicator without changing `running | done | error`.
- Footer/dashboard: optionally show a `? N awaiting reply` count.
- Takeover transcript: render communication directionally, e.g. `↑ question to teamlead` and `↓ teamlead reply`.
- Opening `/subagents` must not consume model-facing messages or answer questions.
- Propagate one root-owned in-process tree registry through hidden child resource-loader bridges; join coordinators by native session id rather than repeated local `sa-N` ids.
- Render running descendant branches under the prompt and the full tracked descendant tree in `/subagents`; qualified nested nodes remain directly selectable and takeover-capable.

### 5. Lifecycle, limits, and error policy

- Bound message/question/reply bodies (proposed: 16 KiB) and stored communication history.
- Session shutdown order:
  1. stop accepting parent sends/replies;
  2. clear deferred parent deliveries;
  3. reject pending child questions;
  4. dispose child scopes/runtime.
- A late reply after timeout/cancel returns an error and never starts a new run accidentally.
- `subagent_send` to a settled child intentionally restarts it and obeys the same four-running-agent cap.
- Parent-session recovery is durable: lifecycle manifest entries link stable public ids to child Pi JSONLs. `/reload` and reopening the same session auto-continue children last marked running/suspended; `/new` leaves the old session's children suspended until that session is resumed. Fork/clone and `/tree` navigation establish a recovery boundary rather than sharing mutable child JSONLs. Recovery continues from finalized transcript state rather than attempting to resurrect an in-flight stream/tool promise.
- Keep `btw` results and communication out of the parent model channel as today.

## Files to change

- `index.ts` — nonblocking wait, two parent tools, message hook/delivery/renderer, lifecycle cleanup.
- `src/prompt.ts` — async-wait workflow, sensible final-message guidance, send/reply strings.
- `src/domain.ts` — run identity, communication events, pending-question snapshot state.
- `src/backend.ts` — reply capability/contract.
- `src/manager.ts` — run-safe settlements, send/reply routing, message hook, wait cleanup.
- `src/backends/pi.ts` — injected child tools and pending-reply bridge.
- `src/backends/stub.ts` — deterministic communication/reply support for tests.
- `src/backends/claude.ts`, `src/backends/codex.ts` — compile-safe unsupported capability handling only; production remains Pi-only.
- `src/result-delivery.ts` — completion-keyed delivery instead of ID-keyed overwrite.
- `src/ui/transcript.ts`, `src/ui/takeover.ts` — communication rendering/status.
- `package.json` — include new test files.
- `docs/design-plan.md` — replace stale blocking/multi-backend behavior documentation.

Suggested new focused modules:

- `src/communication.ts` — IDs, pending request lifecycle, bounds, and pure helpers.
- `communication.test.ts` — request/reply and race tests.
- `async-wait.test.ts` or `index.test.ts` — prove the tool returns immediately and callbacks remain individual.
- `prompt.test.ts` — lock in the no-poll/sensible-final-message guidance.

## Test plan

### Async wait

- Calling wait with running children resolves promptly (no timer/subagent settlement dependency).
- IDs are deduplicated and unknown/hidden IDs still fail.
- Each child completion produces its own callback, in settlement order.
- A wait call never consumes or suppresses a completion.
- Already-settled pending completions still flush; already-emitted completions are not duplicated.
- Repeated wait calls do not duplicate callbacks.
- Run 1 and run 2 completions for the same `sa-N` are both preserved.

### Messaging

- Child async update becomes a parent steer message.
- Child question exposes a stable request ID and remains pending.
- Correct reply resolves the child tool with the exact reply text.
- Wrong child/request pair, duplicate reply, timeout, cancel, and shutdown all fail cleanly.
- Reply beats timeout and timeout beats late reply deterministically.
- Unsolicited parent message steers a running child and restarts a settled child.
- Parent send/reply ordering is preserved.
- A child can send/ask as its first action before the manager event pump has caught up.
- `btw` children do not receive messaging tools and cannot enter the parent model context.

### UI and regressions

- Pending-question markers appear in check/list/takeover and clear on reply.
- Existing result, cancel, pruning, concurrency, takeover, and by-the-way tests remain green.
- Old persisted `subagent-result` messages still render.
- Child completion truncation limits and session-file pointers remain unchanged.

## Acceptance criteria

- No model-facing subagent tool call remains open merely to wait for child completion.
- After `subagent_wait`, the teamlead can produce a concise user-facing interim response and stop; child final messages later resume it individually.
- A running child can update or question the teamlead, and the teamlead can send unsolicited guidance or resolve the exact pending question without deadlock.
- Completion and communication events are not duplicated, overwritten across child restarts, or injected after session shutdown.
- Production spawning remains fixed to in-process Pi with `openai-codex/gpt-5.6-sol`.

## Baseline verification

- `npm test`: 20/20 passing before implementation.
- `npm run check`: the initial inherited config failed through the deployed symlink. Execution made this extension's `tsconfig.json` self-contained; the check now passes.
- Existing uncommitted changes in `index.ts`, `src/prompt.ts`, and `src/runtime.ts` must be preserved.
