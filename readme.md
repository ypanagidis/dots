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

## Editor Tooling

Neovim tools are configured in `modules/ides/nvim-config/` and installed through
Home Manager's `programs.neovim.extraPackages`.

- `oxlint` and `oxfmt` are pinned in `custom-packages/flake.nix` to Oxc's
  upstream `apps_v*` GitHub release binaries. This avoids waiting for nixpkgs
  updates and avoids local Rust/pnpm source builds.
- Tailwind CSS LSP is enabled with custom root detection. The upstream
  nvim-lspconfig Tailwind v4 fallback can use `.git` as a root, which starts a
  monorepo-root server for packages that do not use Tailwind. The local config
  only starts Tailwind when a Tailwind/PostCSS config exists or a nearby
  `package.json` depends on `tailwindcss`, `@tailwindcss/vite`, or
  `@tailwindcss/postcss`.

The previous multi-host and macOS layout is preserved on the `multihost-config` branch.
