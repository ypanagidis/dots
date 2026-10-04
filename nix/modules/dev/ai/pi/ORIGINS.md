# Pi runtime sources

These are owned copies of the extensions selected for this configuration. They
are intentionally not updated from upstream during a Nix build.

- The execution/UI extensions started from `davis7dotsh/my-pi-setup` at
  `73bf4d826f39b5cab6b7865e706ba4a2669629ca`.
- `subagents` was updated from [DevMiner/pi-subagents](https://git.devminer.xyz/DevMiner/pi-subagents)
  at `d930964ab1c867230b7b9734d747389d47cb6a14`. It replaces the older
  `my-pi-setup` copy and uses the existing shared dependency pins.
- `continue-after-compaction`, `git-interceptor`, and `save-md` started from
  `dmmulroy/.dotfiles` at `6285439daa5d0001f50a4ccf74e5fdd2e79aea04`.
- `mcp-adapter` started from `nicobailon/pi-mcp-adapter` v2.26.0 at
  `5ee81b47b571b3c4ac2e68a03812c64e3f95cb98`.

Local fixes and customization should be committed directly here. Upstream can
be consulted manually when we deliberately choose to port a change.

## Local fixes

- `subagents` keeps the repository's shared `tsconfig.json`. Its spawn tool
  accepts GPT-5.6 Sol for coding and GPT-6 Astra for other tasks, rather than
  upstream's fixed Sol model. Checkpoints preserve the selected model across
  restarts. `/btw` uses Astra for one-off questions. The runtime is Pi-only;
  Claude Code and Codex CLI backends remain unused upstream source.

- `workflows` launches its permission-restricted child with the Nix-provided
  `PI_WORKFLOW_NODE`. Pi evaluates extensions under Bun, whose `process.execPath`
  cannot enforce the Node `--permission` sandbox used by this extension.
