# Node and pnpm.

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --log-level quiet)"
fi

export PNPM_HOME="$HOME/.local/share/pnpm"
if [[ -d "$PNPM_HOME/bin" ]]; then
  path=("$PNPM_HOME/bin" $path)
elif [[ -d "$PNPM_HOME" ]]; then
  path=("$PNPM_HOME" $path)
fi

typeset -U path PATH
export PATH
