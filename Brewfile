# Brewfile — packages this dotfiles setup depends on.
# Install everything with:  brew bundle --file=Brewfile
#
# Curated to what the configs actually reference. Add project-specific
# tools (databases, language toolchains, etc.) as you need them.

# ---------- Prompt & shell plugins ----------
brew "starship"                  # prompt (configured in .config/zsh/starship.toml)
# zsh plugins (autosuggestions, vi-mode, history-substring-search,
# fast-syntax-highlighting) are git-cloned on first shell start by
# .config/zsh/plugins.zsh — no brew packages needed for them.

# ---------- Navigation & fuzzy finding ----------
brew "fzf"                       # fuzzy finder (Ctrl-T / Ctrl-R)
brew "fd"                        # fast find, used as fzf's default source
brew "eza"                       # modern ls (l/la/ll/lt aliases)
brew "bat"                       # cat/pager with syntax highlighting (MANPAGER, fzf preview)
brew "ripgrep"                   # rg — fast grep

# ---------- Editor, multiplexer, git ----------
brew "neovim"                    # $EDITOR / $VISUAL (config in .config/nvim)
brew "tmux"                      # terminal multiplexer (.tmux.conf, .config/tmux)
brew "git"
brew "lazygit"                   # git TUI (lg alias)
brew "gh"                        # GitHub CLI

# ---------- Node toolchain ----------
brew "fnm"                       # node version manager (node.zsh, --use-on-cd)
# pnpm is installed via corepack / its own installer into ~/Library/pnpm
# (see README); it is not a brew package here.

# ---------- Misc ----------
brew "gnupg"                     # gpg (GPG_TTY is exported in .zshenv)
brew "wget"

# ---------- Casks ----------
cask "ghostty"                   # terminal emulator (.config/ghostty)
