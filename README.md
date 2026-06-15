# dotfiles

My personal macOS dotfiles: a zsh setup (starship prompt, XDG-clean layout,
git-managed plugins), Neovim, tmux, and Ghostty.

## What's in here

| Path                     | Linked to              | What it is                                  |
| ------------------------ | ---------------------- | ------------------------------------------- |
| `.zshenv`                | `~/.zshenv`            | Bootstrap: inits Homebrew, sets `ZDOTDIR`   |
| `.config/zsh/`           | `~/.config/zsh/`       | The real zsh config (`$ZDOTDIR`)            |
| `.config/nvim/`          | `~/.config/nvim/`      | Neovim (lazy.nvim)                          |
| `.config/ghostty/`       | `~/.config/ghostty/`   | Ghostty terminal                            |
| `.config/tmux/`          | `~/.config/tmux/`      | tmux helper scripts                         |
| `.tmux.conf`             | `~/.tmux.conf`         | tmux config                                 |
| `.config/lazygit/`       | `~/.config/lazygit/`   | lazygit config                              |
| `.config/git/`           | `~/.config/git/`       | global git ignore                           |
| `.gitconfig`             | `~/.gitconfig`         | git user (name/email)                       |
| `Brewfile`               | —                      | minimal packages for this setup             |
| `Brewfile.full`          | —                      | full snapshot of everything installed       |

### How the zsh config is wired

zsh always reads `~/.zshenv` first. This repo's `.zshenv` does two things:
initializes Homebrew, then sets `ZDOTDIR=$XDG_CONFIG_HOME/zsh`. From then on
zsh reads everything (`.zshenv`, `.zshrc`, …) out of `~/.config/zsh/` instead
of `$HOME`, keeping the home directory clean.

`~/.config/zsh/`:

- `.zshenv` — env vars (XDG dirs, `$EDITOR`, `$MANPAGER`, `STARSHIP_CONFIG`, PATH)
- `.zshrc` — history, options, completion; sources the modules below
- `aliases.zsh` · `bindings.zsh` · `fzf.zsh` · `node.zsh` · `prompt.zsh`
- `plugins.zsh` — minimal plugin manager; **clones plugins on first launch** into
  `~/.config/zsh/plugins/` (gitignored). Update them anytime with `zplugin-update`.
- `starship.toml` — prompt theme

---

## Install on a new Mac

Run these steps in order. Everything is copy-pasteable.

### 1. Xcode Command Line Tools (gives you `git`)

```sh
xcode-select --install
```

### 2. Homebrew

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

You don't need to touch `~/.zprofile` as the installer suggests — this repo's
`.zshenv` runs `brew shellenv` for you.

### 3. Clone this repo

```sh
git clone <this-repo-url> ~/Developer/dots
cd ~/Developer/dots
```

> The steps below assume the repo lives at `~/Developer/dots`. If you clone it
> elsewhere, adjust `DOTS` in step 7 accordingly.

### 4. Install the packages

```sh
brew bundle --file=Brewfile
```

To instead mirror the *entire* machine (everything I had installed — extra CLIs,
casks, VSCode extensions), use the full snapshot: `brew bundle --file=Brewfile.full`.

### 5. Node + pnpm

Node is managed by `fnm` (installed in the previous step). Install an LTS and
enable pnpm via corepack:

```sh
fnm install --lts
corepack enable pnpm
```

### 6. Create the XDG state/cache dirs zsh writes to

```sh
mkdir -p ~/.cache/zsh ~/.local/state/zsh ~/.local/bin
```

### 7. Symlink the config into place

```sh
DOTS="$HOME/Developer/dots"

# zsh bootstrap + config
ln -snf "$DOTS/.zshenv"          "$HOME/.zshenv"
ln -snf "$DOTS/.config/zsh"      "$HOME/.config/zsh"

# everything else
mkdir -p "$HOME/.config"
ln -snf "$DOTS/.config/nvim"     "$HOME/.config/nvim"
ln -snf "$DOTS/.config/ghostty"  "$HOME/.config/ghostty"
ln -snf "$DOTS/.config/tmux"     "$HOME/.config/tmux"
ln -snf "$DOTS/.tmux.conf"       "$HOME/.tmux.conf"
ln -snf "$DOTS/.config/lazygit"  "$HOME/.config/lazygit"
ln -snf "$DOTS/.config/git"      "$HOME/.config/git"
ln -snf "$DOTS/.gitconfig"       "$HOME/.gitconfig"
```

> `ln -snf` overwrites an existing symlink in place. If a **real** file/dir is
> already there (e.g. a stock `~/.config/nvim`), move it aside first:
> `mv ~/.config/nvim ~/.config/nvim.bak`.

### 8. Open a new terminal

Start a fresh shell (or `exec zsh`). On first launch `plugins.zsh` clones the
zsh plugins — you'll see "Installing …" lines once, then never again.

That's it. Open Neovim (`nvim`) and lazy.nvim will install its plugins on first
run as well.

### 9. tmux plugins (optional)

`.tmux.conf` uses TPM plugins (`vim-tmux-navigator`, `tmux-yank`). The config
degrades gracefully without them, but to get the full set install TPM and the
plugins:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then start tmux and press `prefix` + `I` (capital i) to install the plugins
(prefix is `Ctrl-s`).

### 10. A Nerd Font (optional, for icons)

The prompt (starship), `eza`, and the tmux status line use Nerd Font glyphs.
Ghostty is set to `Menlo`, which lacks them, so icons may show as boxes until a
Nerd Font is installed and selected:

```sh
brew install --cask font-symbols-only-nerd-font   # or any "*-nerd-font" cask
```

Then set `font-family` in `.config/ghostty/config` to the installed font.

---

## Updating

- **Pull config changes:** `git -C ~/Developer/dots pull` (symlinks mean changes
  apply immediately).
- **Update zsh plugins:** `zplugin-update`
- **Add Homebrew packages:** edit `Brewfile`, then `brew bundle --file=Brewfile`.

## Notes

- macOS already uses zsh as the default login shell, so no `chsh` is needed.
- Plugins, lock files, and caches are gitignored — only source config is tracked.
- `gnupg` is included for git commit signing; `GPG_TTY` is exported in `.zshenv`.
- **Not tracked here:** Karabiner, Zed, Raycast, and other app GUIs. This repo
  covers shell, Neovim, tmux, Ghostty, lazygit, and git.
