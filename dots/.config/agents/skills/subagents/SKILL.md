---
name: subagents
description: Use Pi child agents for delegated or parallel work. Invoke when the user asks for subagents or a workflow with independent child agents.
---

# Subagents

Each subagent is headless, has its own context window, cannot see the parent conversation, cannot ask the user, and cannot spawn subagents or workflows. Give every child a self-contained prompt with paths, constraints, and the expected report.

## Model policy

Use Pi with `openai-codex/gpt-5.6-sol`, high reasoning, and fast mode exclusively.

Every standalone `subagent_spawn` call must set:

- `harness: "pi"`
- `model: "openai-codex/gpt-5.6-sol"`
- `reasoning_effort: "high"`

Pi children load the parent's Pi extensions and settings, including `pi-codex-fast`; the configured fast mode therefore applies to their provider requests. Set the model and reasoning effort explicitly even when the parent already uses them.

Every workflow `agent()` call must set:

- `provider: "openai-codex"`
- `model: "gpt-5.6-sol"`
- `effort: "high"`

## Spawn and manage

Call `subagent_spawn` with a complete `prompt`, short `name`, the required model policy, and `working_dir` when it differs from the current directory. At most four subagents run concurrently.

- `subagent_check({ id })`: peek without blocking.
- `subagent_list()`: list all runs.
- `subagent_wait({ ids })`: block only when results are required to proceed.
- `subagent_cancel({ ids })`: stop runs while preserving partial transcripts.
- `/subagents`: inspect or take over a run interactively.

Results return automatically. After spawning, continue useful parent work instead of immediately waiting.
