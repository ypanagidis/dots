---
name: executor
description: Use the local Executor integration gateway from Pi to discover and call external services, especially Figma and Linear. Trigger for service reads or writes routed through Executor, connection-aware account selection, gateway approvals, or Executor/Pi integration troubleshooting.
---

# Executor

Use Executor's direct `execute`, `skills`, and resume tools. Do not reach for
Pi's generic MCP proxy when the direct Executor tools are available.

## Calling integrations

1. On the first call in a session, load Executor's `execute` guide with the
   `skills` tool.
2. Search the catalog before calling a tool. Use the exact path returned by
   search; do not invent paths or assume a connection owner.
3. Describe an unfamiliar tool before calling it.
4. Combine related reads in one `execute` program when this reduces round trips.
5. Return only the data needed for the task.

When another loaded skill says to call an upstream tool such as `use_figma`,
`get_design_context`, or a Linear issue tool, satisfy that step inside
Executor: search for that named operation, select the intended connection, and
call its returned path from `execute`.

## Selecting accounts

Executor tool paths include the connection owner and connection name. Prefer
the connection whose name matches the user's stated context.

- Figma connections are intended to be named `personal` and `work`.
- If a Figma write could plausibly target either account, ask which account to
  use before executing it.
- For reads, use a file's known account when available. Otherwise call `whoami`
  through each candidate connection or ask the user rather than guessing.
- Never silently fall back from one named connection to the other after an
  authentication or permission failure.

## Approvals and failures

Respect Executor's allow, approval, and block policies. If a call pauses, show
the approval URL or instructions and resume the returned execution instead of
starting the mutation again.

For connection failures, check `/mcp` in Pi, then run
`systemctl --user status executor`. Use `executor open` when integrations,
OAuth connections, or policies need configuration.
