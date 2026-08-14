# Current Package Catalog

This catalogs package, app, tool, plugin, and runtime library declarations currently present in the config. It includes active imports plus inactive Niri modules that still exist in the repo.

## Active System Packages

| Declaration | Location | Packages / apps / libs |
| --- | --- | --- |
| Kernel package set | `configuration.nix` | `pkgs.linuxPackages_6_18` |
| User package | `configuration.nix` | `kdePackages.kate` |
| Enabled programs | `configuration.nix` | `zsh`, `firefox`, `coolercontrol`, `obs-studio` |
| Enabled desktop/session | `configuration.nix` | `sddm`, `plasma6`, `xserver`, `keyd`, `pipewire`, `NetworkManager` |
| Portal package | `configuration.nix` | `kdePackages.xdg-desktop-portal-kde` |
| Virtualization packages | `configuration.nix` | `qemu_kvm`, `gvisor` |
| GPU packages | `configuration.nix` | `config.boot.kernelPackages.nvidiaPackages.production` |
| OBS package and plugins | `configuration.nix` | `obs-studio.override { cudaSupport = true; }`, `obs-vkcapture` |
| `environment.systemPackages` | `configuration.nix` | `vim`, `chromium`, `discord`, `usbutils`, `pciutils`, `alsa-utils`, `pulseaudio`, `pavucontrol`, `git`, `curl`, `wget`, `unzip`, `zip`, `jq`, `ripgrep`, `fd`, `htop`, `nil`, `lm_sensors`, `smartmontools`, `nvme-cli`, `sysstat`, `stdenv.cc.cc.lib`, `fuse3`, `icu`, `zlib`, `nss`, `openssl`, `expat`, `virt-manager`, `gvisor`, `freerdp`, `xfreerdp3-compat`, `libnotify`, `libreoffice-fresh`, `neofetch`, `liquidctl`, `openrgb` |
| Fonts | `configuration.nix` | `nerd-fonts.jetbrains-mono` |
| Systemd service path/interpreter refs | `configuration.nix` | `pciutils`, `bash` |

## Active System Modules

| Declaration | Location | Packages / apps / libs |
| --- | --- | --- |
| Electron install | `modules/electron.nix` | `electron` |
| `nix-ld` Electron runtime libs | `modules/electron.nix` | `stdenv.cc.cc`, `zlib`, `glib`, `nss`, `nspr`, `dbus`, `expat`, `gtk3`, `gdk-pixbuf`, `cairo`, `pango`, `atk`, `at-spi2-atk`, `at-spi2-core`, `libdrm`, `libgbm`, `mesa`, `libglvnd`, `xorg.libX11`, `xorg.libXcomposite`, `xorg.libXdamage`, `xorg.libXext`, `xorg.libXfixes`, `xorg.libXrandr`, `xorg.libXcursor`, `xorg.libXi`, `xorg.libXrender`, `xorg.libXScrnSaver`, `xorg.libxshmfence`, `xorg.libXtst`, `xorg.libxcb`, `xorg.libxkbfile`, `libxkbcommon`, `wayland`, `alsa-lib`, `cups`, `libsecret`, `libnotify`, `libappindicator-gtk3`, `pipewire`, `fontconfig`, `freetype`, `harfbuzz`, `ffmpeg` |
| PrismLauncher override | `modules/minecraft.nix` | `prismlauncher`, `alsa-lib`, `atk`, `at-spi2-atk`, `cairo`, `cups`, `dbus`, `expat`, `glib`, `gtk3`, `libdrm`, `libgbm`, `libxkbcommon`, `mesa`, `nspr`, `nss`, `pango`, `xorg.libX11`, `xorg.libXcomposite`, `xorg.libXdamage`, `xorg.libXext`, `xorg.libXfixes`, `xorg.libXi`, `xorg.libXrandr`, `xorg.libXrender`, `xorg.libXScrnSaver`, `xorg.libXtst`, `xorg.libxcb`, `xorg.libxshmfence` |
| Minecraft scripts | `modules/minecraft.nix` | `mc-prism`, `mc-shaderpack`, `jq`, `curl` |
| Steam | `modules/steam.nix` | `steam`, `proton-ge-bin`, `gamemode`, `steam-hardware` |
| Sunshine | `modules/sunshine.nix` | `sunshine.override { cudaSupport = true; }` |
| KDE Connect | `modules/kdeconnect.nix` | `kdeconnect` |
| Apple Studio Display helper | `modules/crapple-display.nix` | local `asdbctl`, `pkg-config`, `udev` |
| MT7927 Bluetooth kernel modules | `system/mt7927-bluetooth.nix` | local `mt7927-bluetooth-modules`, `kernel.moduleBuildDependencies`, `python3` |
| MT7927 firmware derivations | `system/mt7927-bluetooth.nix` | local `mt7927-bluetooth-firmware`, `python3` |
| MT7927 check script | `system/mt7927-bluetooth.nix` | `mt7927-bt-check`, `kmod`, `ripgrep`, `systemd`, `coreutils`, `bluez`, `util-linux` |

## Active Home Manager Packages

| Declaration | Location | Packages / apps / libs |
| --- | --- | --- |
| Root `home.packages` | `home.nix` | `pnpm`, `nodejs`, `pkgsMaster.codex`, `remmina`, `python3`, `bun`, `httpie`, `pscale`, `high-tide`, `protonup-qt`, `protontricks`, `mangohud`, `ffmpeg-full`, `google-chrome`, `haruna`, `bruno`, `opencode`, `playwright-mcp`, optional `claude`, optional `winapps`, optional `winapps-launcher` |
| CLI programs | `modules/clis/default.nix` | `direnv`, `nix-direnv`, `git`, `eza`, `fzf`, `lazygit`, `gh`, `bat`, `yazi` |
| Shell | `modules/clis/shell/default.nix` | `zsh`, `oh-my-zsh`, `zsh-powerlevel10k`, `fzf` |
| Tmux | `modules/clis/tmux.nix` | `tmux`, `tmuxPlugins.vim-tmux-navigator`, `tmuxPlugins.yank`, `tmuxPlugins.cpu` |
| Btop | `modules/clis/btop/default.nix` | `btop` |
| Terminal | `modules/terminals.nix` | `ghostty` |
| Obsidian | `modules/obsedian.nix` | `obsidian` |
| KDE Home config | `modules/des/kde.nix` | `plasma-manager` config, no direct package list |

## Active IDE And Browser Packages

| Declaration | Location | Packages / apps / libs |
| --- | --- | --- |
| Cursor install | `modules/ides/cursor/default.nix` | local AppImage package from `modules/ides/cursor/cursor.nix` |
| Cursor AppImage extra libs | `modules/ides/cursor/cursor.nix` | `nodejs`, `xorg.libxkbfile`, `libsecret`, `libnotify`, `libappindicator-gtk3`, `curl`, `glib`, `nss`, `nspr`, `at-spi2-atk`, `cups`, `dbus`, `libdrm`, `gtk3`, `pango`, `cairo`, `xorg.libX11`, `xorg.libXcomposite`, `xorg.libXdamage`, `xorg.libXext`, `xorg.libXfixes`, `xorg.libXrandr`, `mesa`, `alsa-lib` |
| T3 Code install | `modules/ides/t3/default.nix` | local `t3-code` AppImage package |
| T3 Code extra libs | `modules/ides/t3/t3.nix` | `libnotify`, `xorg.libxkbfile` |
| VS Code | `modules/ides/vscode/default.nix` | `pkgsMaster.vscode`, `nixfmt` |
| VS Code extensions | `modules/ides/vscode/default.nix` | `vscodevim.vim`, `typescriptteam.native-preview`, `jnoortheen.nix-ide`, `bbenoist.nix`, `esbenp.prettier-vscode`, `dbaeumer.vscode-eslint`, `editorconfig.editorconfig`, `eamodio.gitlens`, `ms-vscode-remote.remote-ssh`, `ms-vscode-remote.remote-ssh-edit`, `sdras.night-owl`, `teabyii.ayu` |
| Neovim plugins | `modules/ides/nvim-config/neovim.nix` | `nvim-lspconfig`, `fidget-nvim`, `conform-nvim`, `blink-cmp`, `nvim-treesitter.withAllGrammars`, `nvim-treesitter-context`, `snacks-nvim`, `nui-nvim`, `nvim-notify`, `noice-nvim`, `mini-nvim`, `bufferline-nvim`, `nvim-web-devicons`, `cyberdream-nvim`, `lualine-nvim`, `oil-nvim`, `yazi-nvim`, `vim-tmux-navigator`, `trouble-nvim`, `nvim-ts-context-commentstring`, `supermaven-nvim`, `which-key-nvim`, `gitsigns-nvim`, `todo-comments-nvim`, `nvim-colorizer-lua`, `render-markdown-nvim` |
| Neovim extra tools | `modules/ides/nvim-config/neovim.nix` | `typescript`, `typescript-language-server`, `tsgo`, `oxlint`, `tailwindcss-language-server`, `gopls`, `prettierd`, `nodePackages.prettier`, `stylua`, `nixfmt-rfc-style`, `go`, `gofumpt`, `gotools`, `golangci-lint`, `delve`, `ripgrep`, `fd`, `lazygit`, `oxfmt`, `yazi` |
| DataGrip | `modules/ides/datagrip/datagrip.nix` | `jetbrains.datagrip` |
| IntelliJ | `modules/ides/intellij/default.nix` | `jetbrains.idea-oss` |
| Helium install | `modules/browsers/helium/default.nix` | local package from `modules/browsers/helium/helium.nix` |
| Helium package deps | `modules/browsers/helium/helium.nix` | `alsa-lib`, `at-spi2-atk`, `at-spi2-core`, `atk`, `bzip2`, `cairo`, `coreutils`, `cups`, `curl`, `dbus`, `expat`, `flac`, `fontconfig`, `freetype`, `gcc-unwrapped.lib`, `gdk-pixbuf`, `glib`, `harfbuzz`, `icu`, `libcap`, `libdrm`, `liberation_ttf`, `libexif`, `libglvnd`, `libkrb5`, `libpng`, `libX11`, `libxcb`, `libXcomposite`, `libXcursor`, `libXdamage`, `libXext`, `libXfixes`, `libXi`, `libxkbcommon`, `libXrandr`, `libXrender`, `libXScrnSaver`, `libxshmfence`, `libXtst`, `libgbm`, `nspr`, `nss`, `libopus.override { withCustomModes = true; }`, `pango`, `pciutils`, `pipewire`, `snappy`, `speechd-minimal`, `systemd`, `util-linux`, `vulkan-loader`, `wayland`, `wget`, `libpulseaudio`, `libva`, `gtk3`, `gtk4`, `qt6.qtbase`, `qt6.qtwayland`, `makeWrapper`, `patchelf`, `adwaita-icon-theme`, `gsettings-desktop-schemas`, `xdg-utils`, `addDriverRunpath` |

## Inactive Niri Packages

These files are not active because `modules/des/default.nix` imports `./kde.nix`, not `./niri`.

| Declaration | Location | Packages / apps / libs |
| --- | --- | --- |
| Niri core | `modules/des/niri/core.nix` | `wl-clipboard`, `jq`, `playerctl`, `brightnessctl` |
| Focus/launch helper | `modules/des/niri/extras/tools/focus-or-launch.nix` | generated `focus-or-launch`, `niri`, `jq`, `bash` |
| Network quick actions | `modules/des/niri/extras/tools/network-actions.nix` | generated `raycast-speedtest`, `raycast-open-ports`, `raycast-public-ip`, `ghostty`, `bash`, `ookla-speedtest`, `iproute2`, `curl` |
| Wallpaper helper | `modules/des/niri/extras/backgrounds/swww-nixos-dark.nix` | generated `set-wallpaper`, `swww`, `nixos-artwork.wallpapers.nineish-dark-gray` |
| Wallpaper helper alternative | `modules/des/niri/extras/backgrounds/swww-nixos-waterfall.nix` | generated `set-wallpaper`, `swww`, `nixos-artwork.wallpapers.waterfall` |
| Waybar configs | `modules/des/niri/extras/bars/*.nix` | `waybar` |
| Switcher | `modules/des/niri/extras/switcher/niriswitcher.nix` | `niriswitcher` |
| Launchers | `modules/des/niri/extras/launchers/*.nix` | `fuzzel`, `anyrun`, Anyrun plugins `libapplications.so`, `libsymbols.so`, `libshell.so` |
| Idle/lock | `modules/des/niri/extras/idle/swayidle.nix` | `swaylock`, `swayidle`, `systemd` |
| Auth/notifications | `modules/des/niri/extras/auth/polkit-gnome.nix`, `modules/des/niri/extras/notifications/mako.nix` | `polkit-gnome`, `mako` |

## Custom Overlay Packages

| Declaration | Location | Packages / apps / libs |
| --- | --- | --- |
| Imported package sets | `custom-packages/flake.nix` | `nixpkgs-unstable`, `nixpkgs-opencode`, `nix-vscode-extensions`, `opencode-flake`, `claude`, `winapps`, `nordvpn-flake` |
| Overlay packages | `custom-packages/flake.nix` | `pscale`, `oxfmt`, `oxlint`, `tailwindcss-language-server`, `tsgo`, `opencode`, `claude`, `nordvpn`, `winapps`, `winapps-launcher` |
| Opencode bun sources | `custom-packages/flake.nix` | `bun` replacement sources for `aarch64-darwin`, `aarch64-linux`, `x86_64-darwin`, `x86_64-linux` |
| Build tools inside overrides | `custom-packages/flake.nix` | `rustPlatform.fetchCargoVendor`, `fetchPnpmDeps`, `pnpm_10`, `pnpm_9`, `go_1_26`, `buildGoModule` |

## Obvious Duplicates And Odd Placements

| Item | Current state |
| --- | --- |
| `ffmpeg` / `ffmpeg-full` | `ffmpeg-full` is user-facing in `home.nix`; `ffmpeg` is a runtime lib in `modules/electron.nix` |
| Browser apps | `chromium` is system-wide, `google-chrome` is user package, `helium` is browser module |
| Shell/CLI tools | Some are enabled as Home Manager programs (`fzf`, `yazi`, `lazygit`), also used as Neovim extra tools or explicit packages |
| `jq`, `curl`, `ripgrep`, `fd`, `lazygit`, `yazi` | Declared in multiple places as global tools, Neovim dependencies, scripts, or inactive Niri helpers |
| Electron runtime libs | Duplicated across generic `nix-ld`, Cursor AppImage wrapper, Helium wrapper, and PrismLauncher override |
| Editor formatting tools | `nixfmt`, `nixfmt-rfc-style`, `prettierd`, `nodePackages.prettier`, `stylua`, `gofumpt`, `oxfmt` are split across VS Code and Neovim |
| System vs user apps | Apps like `discord`, `chromium`, `libreoffice-fresh`, `virt-manager`, `neofetch` are system-wide even though they look user-facing |
| Inactive Darwin condition | `modules/terminals.nix` still has a Darwin `ghostty` branch from the old multihost layout |
| Inactive Niri tree | Niri modules contain many package declarations but are not imported on the current KDE setup |
