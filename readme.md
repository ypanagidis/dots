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

The previous multi-host and macOS layout is preserved on the `multihost-config` branch.
