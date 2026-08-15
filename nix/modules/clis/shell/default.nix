{
  config,
  pkgs,
  dotsLink,
  ...
}:

let
  # The flake lives inside the unified dots repo now.
  flakeDir = "$HOME/Developer/Configs/nix";
  rebuild = "sudo nixos-rebuild switch --flake path:${flakeDir}#nixos";
in

{
  # Same shell as the Arch setup — starship prompt and the dots/ fragment
  # files — but wired the nix way: HM owns .zshrc/.zshenv, and the plugins
  # that dots' plugins.zsh would git-clone at runtime come from nixpkgs
  # instead. On Arch, dots' own .zshenv/.zshrc (via ZDOTDIR) drive the same
  # fragments, so shell behaviour stays identical across both OSes.
  xdg.configFile."zsh".source = dotsLink ".config/zsh";

  # Prompt: starship, reading the shared config from the dots tree (HM points
  # STARSHIP_CONFIG at ~/.config/starship.toml; we make that the dots file).
  programs.starship.enable = true;
  xdg.configFile."starship.toml".source = dotsLink ".config/zsh/starship.toml";

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autocd = true;

    # Declarative equivalents of the dots plugin set.
    autosuggestion.enable = true; # zsh-autosuggestions
    historySubstringSearch.enable = true; # zsh-history-substring-search
    plugins = [
      {
        name = "zsh-vi-mode";
        src = "${pkgs.zsh-vi-mode}/share/zsh-vi-mode";
      }
      {
        name = "fast-syntax-highlighting";
        src = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting";
      }
    ];

    # History behaviour mirrors dots/.config/zsh/.zshrc.
    history = {
      size = 100000;
      save = 100000;
      path = "${config.xdg.stateHome}/zsh/history";
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
    };

    initContent = ''
      setopt NOBEEP
      setopt NUMERIC_GLOB_SORT

      # Completion styling (menu select, case-insensitive), as in dots.
      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

      # From dots prompt.zsh: keep virtualenvs out of the prompt.
      export VIRTUAL_ENV_DISABLE_PROMPT=1
      FUNCNEST=100

      # Shared config fragments from dots/ (fzf keybindings themselves come
      # from programs.fzf's zsh integration; prompt comes from starship above;
      # plugins.zsh is intentionally not sourced — nix provides the plugins).
      for _f in fzf aliases bindings node; do
        source "${config.xdg.configHome}/zsh/''${_f}.zsh"
      done
      unset _f

      # Use Neovim as man-db's pager while keeping `man 2 write` as a normal
      # terminal command. man-db strips formatting on pipes unless this is set.
      export MAN_KEEP_FORMATTING=1
      export MANPAGER='nvim +Man!'
      export MANWIDTH=999

      export LIBVIRT_DEFAULT_URI="qemu:///system"

      # ---------------------------------------------------------
      # NixOS-only rebuild helpers (everything else lives in dots).
      # ---------------------------------------------------------
      alias cn="cd ${flakeDir}"
      alias mc="mc-prism"

      re() {
        pushd ${flakeDir} > /dev/null && ${rebuild} && popd > /dev/null
      }

      # Update the AI agent CLIs (claude-code/codex/opencode/gemini-cli all
      # ride the llm-agents input) and rebuild.
      uai() {
        local original_dir="$PWD"
        cd ${flakeDir} || return 1

        if nix flake update llm-agents; then
          echo "Rebuilding..."
          re
        else
          echo "llm-agents update failed"
        fi

        cd "$original_dir"
      }

      uc() {
        if [[ -z "$1" ]]; then
          echo "Usage: uc <version>"
          return 1
        fi

        local original_dir="$PWD"
        cd ${flakeDir}/modules/ides/cursor || return 1

        if ./update-cursor.sh "$1"; then
          echo "Rebuilding..."
          ${rebuild}
        else
          echo "No update needed or version invalid"
        fi

        cd "$original_dir"
      }

      uh() {
        local original_dir="$PWD"
        cd ${flakeDir}/modules/browsers/helium || return 1

        if ./update-helium.sh "$@"; then
          echo "Rebuilding..."
          ${rebuild}
        else
          echo "No update needed or fetch failed"
        fi

        cd "$original_dir"
      }

      ut3() {
        local original_dir="$PWD"
        cd ${flakeDir}/modules/ides/t3 || return 1

        if ./update-t3.sh "$@"; then
          echo "Rebuilding..."
          ${rebuild}
        else
          echo "No update needed or fetch failed"
        fi

        cd "$original_dir"
      }
    '';
  };
}
