# System Debloat Guide

This repo now includes `debloat-all.sh`, a one-shot cleanup script for this machine.

The script is designed for your setup and does all major cleanup categories:

- user trash and common caches
- browser/electron caches
- Node/Bun/pnpm/npm caches
- Docker build cache/images/containers
- Nix generation trimming + garbage collection
- journal log vacuum

It **explicitly keeps `~/Developer/Work` untouched**.

## What It Cleans

By default, the script cleans:

- `~/.local/share/Trash`
- browser caches (`chrome`, `chromium`, `helium`, Discord cache folders)
- `~/.cache/JetBrains`
- package manager caches (`pnpm`, `npm`, Bun cache dir)
- `node_modules` under `~/Developer`, excluding `~/Developer/Work`
- Docker build cache/images/containers (not volumes by default)
- old Nix system generations (keeps latest 5 by default)
- Nix GC (system + user)
- journal logs (vacuum to size cap)

## Usage

Run from this repo root:

```bash
sudo ./debloat-all.sh
```

You can tune behavior with env vars:

```bash
sudo KEEP_SYSTEM_GENERATIONS=5 JOURNAL_MAX_SIZE=500M PRUNE_DOCKER_VOLUMES=0 ./debloat-all.sh
```

## Important Environment Variables

- `KEEP_SYSTEM_GENERATIONS` (default: `5`)
  - Number of NixOS system generations to keep.
- `PRUNE_DOCKER_VOLUMES` (default: `0`)
  - `1` also prunes unused Docker volumes (can remove DB/data volumes).
- `CLEAN_SANDBOX_NODE_MODULES` (default: `1`)
  - `1` removes `node_modules` under `~/Developer` except `~/Developer/Work`.
- `JOURNAL_MAX_SIZE` (default: `500M`)
  - Target max size for journald logs.

## Examples

Keep 10 Nix generations and also prune Docker volumes:

```bash
sudo KEEP_SYSTEM_GENERATIONS=10 PRUNE_DOCKER_VOLUMES=1 ./debloat-all.sh
```

Skip removing `node_modules` under `~/Developer`:

```bash
sudo CLEAN_SANDBOX_NODE_MODULES=0 ./debloat-all.sh
```

## Notes

- If a cache appears again after cleanup, it is normal; apps recreate caches.
- The script prints before/after disk usage so you can verify reclaimed space.
- For project work, you may need to reinstall dependencies after cleanup.
