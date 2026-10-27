# Pi skill decisions

This document preserves the skill decisions made while designing the personal
Pi setup. Every skill installed by this configuration is a repository-owned
copy under `dots/.config/agents/skills`; upstream repositories are references,
not runtime sources. Home Manager exposes that directory through direct
out-of-store links, so editing a skill does not require a rebuild.

## Integration skills

- **Figma suite** — the complete official Figma workflow and tool-usage skills.
- **linear** — the official Linear issue/project workflow skill.
- **gh-stack** — the stacked branch and pull-request workflow.
- **executor** — translates Figma, Linear, and future integration operations
  into Executor's connection-aware search/describe/execute flow.

These and the engineering/productivity skills below live under
`~/.agents/skills` through Home Manager. Pi and Codex read that directory
directly; Claude Code's `~/.claude/skills` is one Nix-managed symlink to the
same tree. The tree includes the user-invoked `/plannotator-review`,
`/plannotator-annotate`, and `/plannotator-last` commands. Executor and the Pi
MCP adapter are runtime integration rather than additional workflow suites.
The adapter's optional `mcp-scripting` skill is not installed.

## Executor setup

Executor runs on mendbox (CT 170, `nix/hosts/executor`), bound to loopback
and published on the tailnet by `tailscale serve` at
`https://executor.tailc79e49.ts.net`. Pi connects over HTTP with a bearer
token read at connect time from `~/.config/executor/token`; the `executor`
CLI wrapper reads the same file and targets the `mendbox` server profile.
The token, OAuth tokens, and Executor's database stay on the server or in
that file; they never enter Pi's config or the Nix store.

The token itself lives on the server in
`/var/lib/executor/.executor/server-control/auth.json`. To rotate it, run
`runuser -u executor -- env HOME=/var/lib/executor executor server rotate-token`
in the container, restart `executor.service`, and copy the new value to every
client's token file.

OAuth connections must be added through a localhost tunnel. When a provider
supports client ID metadata documents (Atlassian does), Executor's release
build always uses `https://executor.sh/api/oauth/client-id-metadata/local.json`,
which only allows loopback callbacks, so a sign-in started from the `ts.net`
origin fails with "redirect_uri is not registered for client". Instead run
`ssh -N -L 4788:127.0.0.1:4788 root@executor.tailc79e49.ts.net` and open
`http://localhost:4788/?_token=…` for the sign-in. Token refresh happens on
the server, so the tunnel is only needed to connect or re-authorize.

Pi's `settings.json` is materialized as a writable runtime file rather than a
Nix-store symlink. Pi owns interactive preferences such as the selected model,
thinking level, theme, and `/codex-fast` mode, so they survive restarts and
rebuilds. Nix owns the package list and version pins.

1. Run `executor open` to open the web console.
2. Add Linear's MCP source at `https://mcp.linear.app/mcp` and authenticate its
   connection.
3. Add Figma's MCP source at `https://mcp.figma.com/mcp` once. Create two
   connections from that integration, named `personal` and `work`, and complete
   OAuth with the corresponding Figma account for each. Use separate browser
   profiles or a private window if Figma keeps selecting the wrong account.
4. In Pi, open `/mcp`. The `executor` server should be connected. On the first
   run, use `/mcp reconnect executor` if its direct tools are still populating
   the metadata cache.

Executor search results include both the owner scope and connection name, for
example paths containing `.personal.` or `.work.`. Search supplies the exact
callable path; never hard-code the owner segment. Writes with an ambiguous
Figma account require an explicit account choice.

Figma currently restricts its remote MCP server to supported clients. If its
OAuth flow rejects Executor, stop there rather than replacing it with a weaker
REST integration: the REST API does not provide the remote MCP server's full
`use_figma` canvas workflow.

## Engineering and productivity skills

### Automatically invoked

- **coding-standards** — TypeScript standards, derived from Dillon Mulroy's.
  Its Effect references were removed; Effect code goes to `effect-layers`.
  Load the root skill for implementation and standards review, then read only
  the reference branches relevant to the changed behavior.
- **effect-layers** — Effect v4 services, layers, composition roots,
  entrypoints and `ManagedRuntime`, layer tests, and a layer-graph audit.
  Checked against effect 4.0.6 source. On an Effect bump, re-read the files in
  its `references/sources.md`.
- **domain-modeling** — activate when domain terminology, relationships, or
  lifecycle states are actively being established or changed. Merely reading
  an existing `CONTEXT.md` does not invoke the skill.
- **diagnosing-bugs** — activate for bugs, failures, flakes, and performance
  regressions. Establish a red-capable feedback loop before hypothesizing.
- **writing-for-agents** — activate when writing or editing skills, workflows,
  `AGENTS.md`, `CLAUDE.md`, or documents reached through agent pointers.
- **react-best-practices** — Vercel's React/Next.js performance rules
  (waterfalls, bundle size, RSC, re-renders), copied by hand from
  `vercel-labs/agent-skills` because the `skills.sh` installer is not used on
  Nix. Activate when writing, reviewing, or refactoring React or Next.js code.
  Refresh by re-copying `skills/react-best-practices` from upstream.

`grilling` is also installed as the model-invoked primitive used by
`grill-with-docs`; it is infrastructure rather than a separate everyday
workflow.

### User-invoked only

- **grill-with-docs** — conduct a decision interview while maintaining domain
  terminology and durable decisions.
- **tdd** — run the full red-green workflow only when explicitly selected.
  Normal tests remain required by `coding-standards`, and bug regression tests
  remain part of disciplined diagnosis.
- **code-review** — run separate Standards and Spec reviews against an explicit
  fixed point. The Standards reviewer loads the local `coding-standards` skill.
- **prototype** — create throwaway logic or UI prototypes to answer a named
  design question.
- **handoff** — create a portable handoff when moving to another harness,
  directory, person, or context.
- **show-me** — produce the smallest useful visual explanation on request.
- **wait-what** — re-explain the previous response in plain language using the
  project's domain vocabulary.
- **recipe-diagrams** — render recipe dependency graphs as 4K PNGs. It is not a
  general architecture-diagram skill.

User-invoked skills should disable implicit/model invocation. TDD must also be
removed from any workflow that would otherwise select it automatically; a
workflow may use it only after the user explicitly opts in.

### Do not install as separate skills initially

- **codebase-design** — keep separate from Dillon's unchanged standards. Revisit
  it later only as a deliberate alternative or addition.
- **write-discoverable-code** — Dillon's standards already carry the naming and
  searchability guidance we want initially.
- **implement**, **to-spec**, and **to-tickets** — ordinary agent behavior and
  Pi workflows own this process.
- **setup-matt-pocock-skills**, **improve-codebase-architecture**,
  **wayfinder**, and **triage** — useful but too process-heavy for the initial
  setup.
- **research** and **herdr** — Pi workflows, subagents, background terminals,
  and web access own these capabilities.
- **computer-use-mcp**, **wizard**, **teach**, **to-questionnaire**, and
  **worktrees** — add only when a concrete need appears.
- **bro** — superseded by `wait-what`.

## Pi runtime principles

- One owner for each capability: one subagent engine, workflow engine, web
  layer, MCP adapter, question UI, status UI, and memory/compaction strategy.
- Nix/Home Manager owns the Pi binary, extension and skill sources, workflow
  definitions, settings, themes, and external package pins.
- Pi retains writable ownership of sessions, authentication, caches, and
  temporary workflow state.
- Language-server feedback is part of the initial setup, but repository
  typecheck, lint, test, and build commands remain authoritative.
