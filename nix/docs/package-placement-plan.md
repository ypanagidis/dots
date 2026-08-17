# Package Placement Plan

This was the proposed target organization before the package move. The implemented result is cataloged in `docs/package-catalog-after.md`.

## Principles

| Rule | Decision |
| --- | --- |
| System config owns hardware, boot, services, drivers, daemons, virtualization, and packages needed by services. | Keep these in `configuration.nix` or focused `system/*.nix` / `modules/*.nix` system modules. |
| Home Manager owns user-facing GUI apps, editors, terminal tools, shell tools, and desktop app config. | Move daily apps out of `environment.systemPackages` unless they are needed by a system service. |
| Runtime libraries stay with the wrapper or compatibility layer that needs them. | Do not globally install wrapper-only libs just to reduce list length. Instead rename/group their modules clearly. |
| Generated helper scripts stay next to the workflow they support. | Minecraft scripts stay with Minecraft, Niri scripts stay with Niri, MT7927 check stays with MT7927. |
| Tool dependencies should be local when they only support one tool. | Neovim LSP/formatter dependencies should remain in `programs.neovim.extraPackages`; script dependencies should be referenced by absolute store path. |
| Global CLI tools should exist once as user tools. | Avoid installing the same interactive CLI via system packages and Home Manager unless required by a system script. |

## Proposed File Layout

| File | Responsibility |
| --- | --- |
| `configuration.nix` | Imports and high-level system options only. Keep host identity, boot, user account, networking, desktop session, audio, virtualization, graphics, fonts, and state version here. |
| `home.nix` | Imports and high-level Home Manager options only. Keep `home.stateVersion`, session path, SSH config, and imports here. Avoid long package lists here. |
| `modules/system/base-packages.nix` | Low-level system CLI/debug/runtime packages that should be available root/system-wide: `vim`, `git`, `curl`, `wget`, `unzip`, `zip`, `jq`, `pciutils`, `usbutils`, `htop`, `nil`, hardware diagnostics, runtime libs needed globally. |
| `modules/system/desktop-kde.nix` | System side of KDE: `xserver`, `sddm`, `plasma6`, portal, keyd, pipewire, fonts, KDE packages. |
| `modules/system/virtualisation.nix` | Docker, libvirt, `qemu_kvm`, `gvisor`, `virt-manager` if you want it system-wide. |
| `modules/system/gpu.nix` | NVIDIA driver package, graphics settings, OBS CUDA package if we treat OBS as hardware/GPU-sensitive. |
| `modules/apps/gui.nix` | User-facing GUI apps: `discord`, `libreoffice-fresh`, `bruno`, `haruna`, `high-tide`, `remmina`, browser choices, `obsidian` import if desired. |
| `modules/apps/browsers/default.nix` | Browser ownership: keep `helium` here, decide whether `chromium` and `google-chrome` belong here or whether one should be removed. |
| `modules/dev/base.nix` | Developer CLIs: `pnpm`, `nodejs`, `bun`, `python3`, `httpie`, `pscale`, `opencode`, `playwright-mcp`, `codex`, optional `claude`. |
| `modules/dev/editors/default.nix` | Existing editor imports: Neovim, VS Code, Cursor, T3, DataGrip, IntelliJ. |
| `modules/media/default.nix` | Media/user tools: `ffmpeg-full`, possibly `mpv`/video tools later. |
| `modules/gaming/default.nix` | Home/user gaming tools: `protonup-qt`, `protontricks`, `mangohud`. System gaming modules keep `steam`, `gamemode`, and PrismLauncher wrapper if you prefer system-wide. |
| `modules/compat/electron-runtime.nix` | Rename current `modules/electron.nix`; keep `nix-ld` and Electron runtime library list here. Consider not installing `electron` itself unless you actually use the Electron binary. |
| `packages/helium.nix`, `packages/cursor.nix`, `packages/t3-code.nix` | Optional future cleanup: move local package derivations out of modules so modules only install/configure packages. |
| `system/mt7927-bluetooth.nix` | Keep as-is: hardware-specific kernel module/firmware/check script. |

## Proposed Moves

| Current location | Move / keep | Reason |
| --- | --- | --- |
| `home.nix` long `home.packages` list | Split across `modules/dev/base.nix`, `modules/apps/gui.nix`, `modules/media/default.nix`, `modules/gaming/default.nix`, and browser module | Keeps `home.nix` as an entrypoint instead of a junk drawer. |
| `configuration.nix` long `environment.systemPackages` list | Split into `modules/system/base-packages.nix`, `modules/system/virtualisation.nix`, `modules/system/gpu.nix`, app modules, and hardware modules | Separates system dependencies from user apps. |
| `ffmpeg-full` in `home.nix` | Move to `modules/media/default.nix` | User-facing media tool, not editor/system config. |
| `ffmpeg` in `modules/electron.nix` | Keep in renamed `modules/compat/electron-runtime.nix` | It is a runtime library for external Electron binaries, not the user-facing FFmpeg app. |
| `discord`, `libreoffice-fresh`, `neofetch` in `configuration.nix` | Move to Home Manager app/CLI modules | User-facing, no obvious system-service need. |
| `chromium` in `configuration.nix`, `google-chrome` in `home.nix`, `helium` in browser module | Consolidate in browser module and decide preferred installed browsers | Browser policy should live in one place. |
| `virt-manager` in `configuration.nix` | Either keep with libvirt in `modules/system/virtualisation.nix` or move to GUI apps | It controls a system service but is a user GUI. I lean keeping it with virtualisation. |
| `gvisor` in `configuration.nix` and Docker runtime path | Keep with Docker in `modules/system/virtualisation.nix`; remove from generic system package list if not needed interactively | It is primarily a Docker runtime dependency. |
| `stdenv.cc.cc.lib`, `fuse3`, `icu`, `zlib`, `nss`, `openssl`, `expat` in `configuration.nix` | Move to a clearly named runtime/compat module only if needed globally, otherwise remove after testing | These look like historical runtime libs and may now be covered by `nix-ld` or wrappers. Risky removal should be tested separately. |
| `pulseaudio` package in `configuration.nix` while `services.pulseaudio.enable = false` | Remove if no command-line tool depends on it, keep `pulseaudio` compat via PipeWire only | Likely redundant with PipeWire unless you need `pactl` from PulseAudio package. |
| `ripgrep`, `fd`, `lazygit`, `yazi` duplicated globally and in Neovim extraPackages | Keep globally via Home Manager programs; keep in Neovim extraPackages only if Neovim needs store-pathed deps independent of shell PATH | Avoid accidental Neovim breakage; can dedupe later after confirming plugin behavior. |
| `nixfmt` in VS Code and `nixfmt-rfc-style` in Neovim | Pick one formatter package for Nix and expose it consistently | Current mixed names are confusing. |
| `jq` globally, in Minecraft script, in Niri helpers, in MT7927 check path | Keep global `jq` for user CLI, keep absolute `pkgs.jq` refs in scripts | Script refs are not duplicate installs in the same sense; they make scripts reproducible. |
| `electron` package in `modules/electron.nix` | Consider removing if you only need `nix-ld` libs for external Electron apps | The module name suggests runtime compatibility, not necessarily installing Electron itself. |
| `modules/terminals.nix` Darwin branch | Remove from main | Main is now Linux-only. |
| Inactive `modules/des/niri` package declarations | Keep but mark as inactive, or move to `modules/des/niri/` unchanged | No behavior impact. If you want simple main, delete Niri from main and leave it on `multihost-config`. |

## Proposed Review Decisions

| Decision | Recommendation |
| --- | --- |
| Browser set | Keep `helium` as default plus either `chromium` or `google-chrome`, not both unless you want both. |
| Niri tree | Delete from main if the goal is a simple KDE-only config; keep on `multihost-config`. |
| Electron compatibility | Rename `modules/electron.nix` to `modules/compat/electron-runtime.nix`; keep `ffmpeg` there as a runtime lib. |
| Global runtime libs | Move to a named compatibility module first, then prune with rebuild testing. |
| Neovim tool deps | Do not dedupe aggressively yet; editor-local tool dependencies are safer. |
| User apps currently system-wide | Move to Home Manager unless they are services, drivers, or service dependencies. |

## After Approval

1. Create the target module files.
2. Move package lists without changing package content unless you approve removals.
3. Remove stale Darwin branch in `modules/terminals.nix`.
4. Optionally remove inactive Niri modules from main if approved.
5. Run `nixfmt` and `nix eval path:/home/yiannis/nixcfg#nixosConfigurations.nixos.config.system.build.toplevel.drvPath`.
6. Write `docs/package-catalog-after.md` and compare it with `docs/package-catalog-current.md`.
