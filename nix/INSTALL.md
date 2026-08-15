# Fresh NixOS install (Aug 2026)

Partitioning is declarative via **disko** (`disk-config.nix`), so the whole
install is three commands from the ISO. The 2 TB Samsung gets wiped; the 1 TB
Windows disk is not touched.

## 1. Boot a NixOS graphical/minimal ISO and get the repo

```sh
sudo -i
nix-shell -p git
git clone https://github.com/ypanagidis/dots /root/Configs
cd /root/Configs/nix
```

## 2. Partition + mount with disko (DESTROYS the 2 TB disk)

```sh
nix --experimental-features "nix-command flakes" run \
  github:nix-community/disko/latest -- --mode destroy,format,mount ./disk-config.nix
```

This creates: 1 GB ESP at `/boot`, btrfs root with `@root` `@home` `@nix`
`@log` subvolumes (zstd, noatime), everything mounted under `/mnt`.

## 3. Refresh hardware config (no filesystems — disko owns those)

```sh
nixos-generate-config --no-filesystems --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix ./hardware-configuration.nix
git add hardware-configuration.nix   # flakes only see tracked files
```

## 4. Install

```sh
nixos-install --flake .#nixos
```

## 5. After first boot

- Move the repo into place: `mkdir -p ~/Developer && cp -r /root/Configs ~/Developer/Configs`
  (or re-clone; `modules/dots.nix` expects `~/Developer/Configs/dots`).
- Restore the backup: `tar -I zstd -xf backup-yiannis-2026-08-15.tar.zst -C ~`
  (brings back `Developer/`, `.ssh`, `.codex`, `.claude`). Restore AFTER the
  clone check — the tarball's `Developer/Configs` may be older than the repo.
- ghostty/tmux/nvim configs are symlinked from `dots/` by their nix modules
  (packages and language tooling stay declarative in nix); zsh/btop remain
  nix-native for now (see `modules/dots.nix` header).

## Notes

- `stateVersion` is `26.05` for system and home — set at install time, never
  bump it afterwards.
- AI agents (claude-code, codex, opencode, gemini-cli) come from the
  `llm-agents` flake input via `modules/dev/ai.nix`; extend the list there.
- KDE Plasma comes from `nixos-unstable` (6.7.x at time of writing).
- Bootloader is systemd-boot; the old Limine setup died with the wipe.
