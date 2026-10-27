# Configs

Personal workstation configuration in one repository. The setup has three layers:

1. `dots/` contains the live configuration files.
2. `nix/` declares the NixOS system, packages, services, and Home Manager links.
3. `nix/modules/dev/ai/` builds the coding-agent environment around Pi and shared skills.

The primary machine is NixOS. macOS uses the same `dots/` tree with Homebrew and manual symlinks.

## The `dots/` and `nix/` story

### Repository layout

| Path | Purpose |
| --- | --- |
| `dots/` | Raw dotfiles, shared agent skills, helper scripts, and Brewfiles |
| `nix/` | NixOS flake, Home Manager configuration, packages, and services |
| `nix/INSTALL.md` | Fresh NixOS installation runbook using disko |
| `nix/readme.md` | Nix layout, package ownership, and editor tooling notes |
| `rust/niri-ctx/` | Rust workspace dispatcher for the niri workflow |
| `install.sh` | Builds and links `niri-ctx` for a manual Linux setup |
| `tests/` | Live convergence checks for the niri workflow |
| `docs/pi-skills.md` | Decisions and setup notes for Pi, skills, and integrations |

The repository is expected at `~/Developer/Configs`. Home Manager builds its live links from that path in `nix/modules/dots.nix`.

### Ownership model

`nix/` owns the reproducible machine state:

- NixOS and Home Manager modules
- packages, services, desktop sessions, and hardware configuration
- coding-agent binaries and Pi extension dependencies
- generated configuration that should be declarative

`dots/` owns editable configuration content:

- zsh, Neovim, tmux, Ghostty, Alacritty, btop, lazygit, and git
- KDE, niri, herdr, and workflow helpers
- shared coding-agent skills
- VSCode settings used by the macOS setup

Home Manager uses `mkOutOfStoreSymlink` to link selected files directly from `dots/`. Editing a linked file takes effect immediately without a rebuild. The corresponding Nix module still owns the package and any system integration.

### NixOS setup

For a fresh machine, follow [`nix/INSTALL.md`](nix/INSTALL.md). It covers the destructive disko step, hardware configuration, installation, and first-boot restore.

For a normal rebuild:

```sh
cd ~/Developer/Configs/nix
sudo nixos-rebuild switch --flake .#nixos
```

The shell also provides:

```sh
re    # rebuild from anywhere
cn    # enter the nix directory
uai   # update the llm-agents input and rebuild
```

The system and Home Manager `stateVersion` values are both `26.05`. They are installation compatibility values and should not be bumped with routine updates.

### Shared dotfiles

| Source in `dots/` | Live location | Purpose |
| --- | --- | --- |
| `.config/zsh/` | `~/.config/zsh/` | Shell configuration and prompt |
| `.config/nvim/` | `~/.config/nvim/` | Neovim and lazy.nvim |
| `.config/ghostty/` | `~/.config/ghostty/` | Ghostty terminal |
| `.config/alacritty/` | `~/.config/alacritty/` | Alacritty terminal |
| `.tmux.conf` | `~/.tmux.conf` | tmux configuration |
| `.config/tmux/` | `~/.config/tmux/` | tmux helper scripts |
| `.config/btop/` | `~/.config/btop/` | btop configuration and theme |
| `.config/lazygit/` | `~/.config/lazygit/` | lazygit configuration |
| `.config/git/ignore` | `~/.config/git/ignore` | Global git ignore rules |
| `.config/herdr/` | `~/.config/herdr/` | herdr session configuration |
| `.config/niri/` | `~/.config/niri/` | niri session and workflow |
| `.config/agents/skills/` | `~/.agents/skills/` | Shared coding-agent skills |

On a manual shell setup, `dots/.zshenv` initializes Homebrew when present and sets `ZDOTDIR=$XDG_CONFIG_HOME/zsh`. zsh then reads the real environment, shell, plugin, Node, and prompt configuration from `~/.config/zsh/`.

`plugins.zsh` clones its small plugin set into `~/.config/zsh/plugins/` on first launch. Run `zplugin-update` to refresh those checkouts.

### niri workflow

The three-monitor niri workflow is driven by `niri-ctx`, a Rust CLI in `rust/niri-ctx/`. The original Bash implementation remains at `dots/bin/niri-ctx` as a rollback path.

NixOS packages the dispatcher through the flake. For a manual Linux setup:

```sh
./install.sh          # build and link the Rust dispatcher
./install.sh --bash   # link the Bash implementation
```

See [`dots/.config/niri/WORKFLOW.md`](dots/.config/niri/WORKFLOW.md) for the workspace model, hotkeys, and debugging commands. `tests/converge.sh` is the live convergence contract.

## Coding agents and Pi

Nix manages the coding-agent stack under `nix/modules/dev/ai/`. It owns binaries, version pins, extensions, and services. Sessions, authentication, caches, and interactive preferences remain writable runtime state.

### Installed agents

The `llm-agents` flake supplies:

- Pi
- Claude Code
- Codex
- OpenCode
- Gemini CLI

Update the shared input and rebuild with `uai`. Add or remove non-Pi agents in `nix/modules/dev/ai/llms.nix`.

### Subscription pooling with CLIProxyAPI

`nix/modules/dev/ai/cliproxyapi.nix` installs upstream CLIProxyAPI from the
existing `llm-agents` pin and runs it as a user service at `127.0.0.1:8317`.
One local package patch removes upstream's `about:blank` browser probe, which
otherwise triggers a KIO missing-file dialog during login on KDE.
It uses `fill-first` routing: requests use the first available account for the
requested model, then try another account when that credential hits a limit.
Codex and Claude have separate account pools. An exhausted Claude pool does
not switch to a Codex model, or vice versa.

After rebuilding, check the service and add each subscription:

```sh
systemctl --user status cliproxyapi

cliproxyapi -codex-login    # repeat for each ChatGPT/Codex account
cliproxyapi -claude-login   # repeat for each Claude account
```

Choose a different account in the browser for each login. Logging into the same
account again refreshes its credentials rather than adding another subscription.
For a browserless Codex login, use `cliproxyapi -codex-device-login`.
To open an authorization URL manually, add `-no-browser` to either login command.
The service watches the auth directory, so adding accounts needs no restart.

Run the agents through the pool with:

```sh
codex-proxy                # accepts the usual Codex arguments and subcommands
claude-proxy               # accepts the usual Claude Code arguments
```

These launchers select the local proxy for that process. Plain `codex` and
`claude` keep their existing configuration. Editors and other agent hosts must
also use the proxy launcher or configure the endpoint themselves. OpenAI API
clients use `http://127.0.0.1:8317/v1`; Anthropic API clients use
`http://127.0.0.1:8317`. Their client key is in
`~/.local/state/cliproxyapi/api-key`.

The local management panel is at `http://127.0.0.1:8317/management.html`.
Its separate login key is in `~/.local/state/cliproxyapi/management-key`.
Use the panel to inspect accounts, disable one, or set credential priorities
if you want a particular account used first. Higher priorities win; login
order alone does not determine routing order.

Tokens live in `~/.local/state/cliproxyapi/auth/`. Keys and the writable runtime
configuration live alongside it, with private permissions. These paths follow
Home Manager's `xdg.stateHome` if customized. No credentials enter the repository
or Nix store. Service starts regenerate `config.yaml` from the Nix baseline,
so change persistent server/routing settings in the module. Account files,
keys, and saved quota cooldowns survive restarts. The pool can return to an
earlier account once its cooldown expires.

```sh
journalctl --user -u cliproxyapi -f
systemctl --user restart cliproxyapi
```

Failover needs another account that can serve the requested model. If every
matching account is exhausted, the request still fails. A stream that has
already delivered output cannot be transparently replayed on another account.

References: [upstream configuration](https://github.com/router-for-me/CLIProxyAPI/blob/v8.0.28/config.example.yaml),
[Codex custom providers](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers),
and [Claude Code gateway configuration](https://code.claude.com/docs/en/llm-gateway-connect).

The browser regression check uses a fake opener and never completes a login:

```sh
python tests/cliproxyapi-browser.py "$(command -v cli-proxy-api)"
```

### Shared skills

The repository-owned skill tree lives at:

```text
dots/.config/agents/skills/
```

Home Manager exposes the same editable tree at:

```text
~/.agents/skills   # Pi, Codex, OpenCode, and other compatible agents
~/.claude/skills   # Claude Code
```

There is one source of truth. Skill edits do not require a rebuild. The tree includes Claude's `/plannotator-review`, `/plannotator-annotate`, and `/plannotator-last` commands. The selection rationale and integration notes are documented in [`docs/pi-skills.md`](docs/pi-skills.md).

### Pi runtime

`nix/modules/dev/ai/pi/` owns the Pi installation:

- `extensions/` contains the vendored and locally maintained extensions.
- `themes/` contains the managed Pi theme.
- `package.json` and `package-lock.json` pin the shared extension dependency graph.
- `ORIGINS.md` records upstream sources and local changes.
- Home Manager links the runtime into `~/.pi/agent/`.

The setup includes workflows, subagents, background terminals, file search, git context, save-to-Markdown support, Pi Lens integration, web access, Plannotator, the Executor MCP adapter, and the interactive question UI.

`settings.json` stays writable so model, thinking, theme, and speed choices survive rebuilds. Nix merges in the declarative baseline and always owns the package pins. `mcp.json`, extensions, themes, and runtime dependencies remain declarative.

### Executor integrations

Executor is the integration gateway used by Pi and Claude Code for Figma, Linear, and future services. It runs on mendbox in an unprivileged NixOS LXC (CT 170, `nix/hosts/executor`) and is reachable only on the tailnet at `https://executor.tailc79e49.ts.net`. The tailnet policy admits member devices and `tag:mend` VMs on port 443; Executor's bearer token is required on top of that.

Clients read the token from `~/.config/executor/token` (mode 600). Pi and the `executor` CLI wrapper pick it up from there; Claude Code gets it through `~/.config/executor/mcp-headers`, a `headersHelper` script.

1. Open the web console with `executor open`.
2. Add Linear from `https://mcp.linear.app/mcp` and authenticate it.
3. Add Figma from `https://mcp.figma.com/mcp`.
4. Create separate Figma connections named `personal` and `work`.
5. Open `/mcp` in Pi and confirm that `executor` is connected.
6. If tools are still loading on first use, run `/mcp reconnect executor`.

Deploy changes to the container with `nixos-rebuild switch --flake .#executor --target-host root@executor.tailc79e49.ts.net` from `nix/`. Tailscale SSH asks for a browser check every 12 hours. If the tailnet is down, `pct enter 170` on mendbox still works. More detail, including the Figma account-selection rules, is in [`docs/pi-skills.md`](docs/pi-skills.md).

## macOS setup

The Nix flake is NixOS-only. A Mac uses the `dots/` tree directly with Homebrew.

### 1. Install Xcode Command Line Tools

```sh
xcode-select --install
```

### 2. Install Homebrew

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

There is no need to add `brew shellenv` to `~/.zprofile`. The repository's `.zshenv` handles it.

### 3. Clone the repository

```sh
git clone https://github.com/ypanagidis/dots ~/Developer/Configs
cd ~/Developer/Configs
```

### 4. Install packages

```sh
brew bundle --file=dots/Brewfile
```

For the larger historical snapshot, including extra applications and VSCode extensions:

```sh
brew bundle --file=dots/Brewfile.full
```

### 5. Install Node and enable pnpm

`fnm` comes from the Brewfile and is initialized by `dots/.config/zsh/node.zsh`.

```sh
fnm install --lts
corepack enable pnpm
```

### 6. Create local state directories

```sh
mkdir -p ~/.cache/zsh ~/.local/state/zsh ~/.local/bin
```

### 7. Link the configuration

```sh
DOTS="$HOME/Developer/Configs/dots"

mkdir -p "$HOME/.config" "$HOME/.agents" "$HOME/.claude"

ln -snf "$DOTS/.zshenv"          "$HOME/.zshenv"
ln -snf "$DOTS/.config/zsh"      "$HOME/.config/zsh"
ln -snf "$DOTS/.config/nvim"     "$HOME/.config/nvim"
ln -snf "$DOTS/.config/ghostty"  "$HOME/.config/ghostty"
ln -snf "$DOTS/.config/tmux"     "$HOME/.config/tmux"
ln -snf "$DOTS/.tmux.conf"       "$HOME/.tmux.conf"
ln -snf "$DOTS/.config/lazygit"  "$HOME/.config/lazygit"
ln -snf "$DOTS/.config/git"      "$HOME/.config/git"
ln -snf "$DOTS/.gitconfig"       "$HOME/.gitconfig"

ln -snf "$DOTS/.config/agents/skills" "$HOME/.agents/skills"
ln -snf "$DOTS/.config/agents/skills" "$HOME/.claude/skills"

VSCODE="$HOME/Library/Application Support/Code/User"
mkdir -p "$VSCODE"
ln -snf "$DOTS/Library/Application Support/Code/User/keybindings.json" "$VSCODE/keybindings.json"
ln -snf "$DOTS/Library/Application Support/Code/User/settings.json"    "$VSCODE/settings.json"
```

`ln -snf` replaces an existing symlink. If a real file or directory already exists at a destination, move it aside first.

### 8. Start a new shell

Run `exec zsh` or open a new terminal. The zsh plugins install on first launch. Opening Neovim installs its lazy.nvim plugins on first use.

### 9. Install tmux plugins

The tmux config works without TPM, but the full plugin set requires it:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Start tmux and press `Ctrl-s`, then `I` to install the plugins.

### 10. Install a Nerd Font if needed

```sh
brew install --cask font-symbols-only-nerd-font
```

Select the installed font in `dots/.config/ghostty/config` if icons render as boxes.

### macOS maintenance

- Pull changes with `git -C ~/Developer/Configs pull`.
- Update zsh plugins with `zplugin-update`.
- Add packages to `dots/Brewfile`, then rerun `brew bundle --file=dots/Brewfile`.
- macOS already uses zsh as the login shell, so no `chsh` is needed.
- Karabiner, Raycast, and other GUI-only application state are not managed here.
