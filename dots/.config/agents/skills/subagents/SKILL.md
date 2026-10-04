---
name: subagents
description: Use Pi child agents for delegated or parallel work. Invoke when the user asks for subagents or a workflow with independent child agents.
---

# Subagents

Each child is a headless Pi session with its own context window. It cannot see the parent conversation or ask the user directly. Give it a self-contained prompt with paths, constraints, and a required final report covering findings, changed files, verification, and blockers.

## Model policy

Choose by task, with high reasoning and the configured fast mode:

- All coding tasks, including implementation, debugging, tests, refactoring, and code review: `openai-codex/gpt-5.6-sol`.
- Everything else, including research, planning, analysis, and writing: `openai-codex/gpt-6-astra`.

Every `subagent_spawn` call must set `model` explicitly and `reasoning_effort: "high"`. The backend is always Pi, so omit `harness`. Children load Pi's extensions and settings, including the configured speed preference.

For an explicitly requested workflow, use the same task-based choice with `provider: "openai-codex"`, the bare model id, and `effort: "high"` in each `agent()` call.

## Spawn and manage

Call `subagent_spawn` with a complete `prompt`, short `name`, the model policy above, and `working_dir` when it differs from the current directory. At most four subagents run concurrently per coordinator.

After spawning, continue useful independent work. Each completed run sends its own final-response callback.

- `subagent_check({ id })`: peek without blocking.
- `subagent_list()`: list runs.
- `subagent_wait({ ids })`: register an asynchronous wait and return immediately. Call once for the runs you need, then continue useful work or end the turn for callbacks. Do not poll.
- `subagent_send({ id, message })`: send guidance. A settled child starts another run.
- `subagent_reply({ id, request_id, message })`: answer a child's blocking question using its exact request id.
- `subagent_cancel({ ids })`: stop runs while preserving partial transcripts.
- `/subagents`: inspect or take over a run interactively.

Children use `teamlead_send` for material updates and `teamlead_ask` when they need a decision. Answer blocking questions before waiting for completion.

## Recursive delegation

`allowed_subagents_depth` defaults to `0`. Set it to `1` only when the child needs to create leaf subagents, or higher for additional generations. Every nested spawn must decrease the remaining allowance. Apply the same model policy to descendants. Children cannot run workflows.

A child remains responsible for its background work until the relevant callbacks arrive and it verifies the results. Treat its final report, not an interim update, as completion.
