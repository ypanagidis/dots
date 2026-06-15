# ~/.zshenv — read for every zsh invocation, before any other config.
#
# Its only job is to bootstrap the real configuration, which lives under
# $ZDOTDIR ($XDG_CONFIG_HOME/zsh). Everything else is sourced from there.

# ---------- Homebrew ----------
# Because ZDOTDIR is set below, zsh reads $ZDOTDIR/.zprofile instead of
# ~/.zprofile, so the usual `brew shellenv` line in ~/.zprofile is skipped.
# Initialize Homebrew here so its tools are on PATH for every shell.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"        # Apple Silicon
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"           # Intel
fi

# ---------- Point zsh at the XDG config dir ----------
# The real .zshenv / .zshrc and friends live in $ZDOTDIR.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
