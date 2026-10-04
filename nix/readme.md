# NixOS Config

Simple single-machine NixOS flake for the desktop.

## Layout

```text
flake.nix                 # NixOS flake output
configuration.nix         # System configuration
hardware-configuration.nix
home.nix                  # Home Manager config for yiannis
system/                   # Local hardware-specific modules and firmware notes
modules/system/           # Host/system package groups
modules/apps/             # User-facing GUI app groups
modules/dev/              # Developer CLI/app groups
modules/media/            # User media tools
modules/gaming/           # User gaming helpers
modules/compat/           # Runtime compatibility layers, such as nix-ld
modules/                  # Remaining reusable Home Manager and system modules
docs/                     # Package catalogs and refactor notes
custom-packages/flake.nix # Custom package overlay
```

## Build

```bash
sudo nixos-rebuild switch --flake .#nixos
```

## Updates

`nix flake update` moves every input. The shell helpers in
`modules/clis/shell/default.nix` do targeted bumps:

- `re`: rebuild and switch.
- `uai`: update the `llm-agents` input (claude-code, codex, opencode,
  gemini-cli), then rebuild.
- `uh`: update the `helium-flake` input, then rebuild.
- `uc <version>`: bump the Cursor AppImage pin, then rebuild.

T3 Code updates itself from its nightly feed, as on macOS. The pin in
`modules/ides/t3/default.nix` only seeds a fresh install.

## Editor Tooling

Neovim and its tools are installed through `home.packages` in
`modules/ides/nvim-config/neovim.nix`.

- `oxlint` and `oxfmt` come from nixpkgs.
- `tsgo` is nixpkgs `typescript` (the TypeScript 7 Go port) exposed under that
  name; `typescript_5` still provides `tsc`/`tsserver` for `ts_ls`.
- Tailwind CSS LSP is enabled with custom root detection. The upstream
  nvim-lspconfig Tailwind v4 fallback can use `.git` as a root, which starts a
  monorepo-root server for packages that do not use Tailwind. The local config
  only starts Tailwind when a Tailwind/PostCSS config exists or a nearby
  `package.json` depends on `tailwindcss`, `@tailwindcss/vite`, or
  `@tailwindcss/postcss`.

The previous multi-host and macOS layout is preserved on the `multihost-config` branch.
