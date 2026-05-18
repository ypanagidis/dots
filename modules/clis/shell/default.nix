{ pkgs, lib, ... }:

let
  linuxRebuild = "sudo nixos-rebuild switch --flake path:$HOME/nixcfg#nixos";

  linuxUpdateHelpers = lib.optionalString pkgs.stdenv.isLinux ''
    uc() {
        if [[ -z "$1" ]]; then
          echo "Usage: uc <version>"
          return 1
        fi

        local original_dir="$PWD"
        cd ~/nixcfg/modules/ides/cursor || return 1

        if ./update-cursor.sh "$1"; then
          echo "Rebuilding..."
          ${linuxRebuild}
        else
          echo "No update needed or version invalid"
        fi

        cd "$original_dir"
    }
    uh() {
      local original_dir="$PWD"
      cd ~/nixcfg/modules/browsers/helium || return 1

      if ./update-helium.sh "$@"; then
        echo "Rebuilding..."
        ${linuxRebuild}
      else
        echo "No update needed or fetch failed"
      fi

      cd "$original_dir"
    }
    ut3() {
      local original_dir="$PWD"
      cd ~/nixcfg/modules/ides/t3 || return 1

      if ./update-t3.sh "$@"; then
        echo "Rebuilding..."
        ${linuxRebuild}
      else
        echo "No update needed or fetch failed"
      fi

      cd "$original_dir"
    }
  '';
in

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "powerlevel10k/powerlevel10k";
      plugins = [
        "git"
        "sudo"
        "docker"
        "kubectl"
        "npm"
        "fzf"
        "z"
        "vi-mode"
      ];
      extraConfig = ''
        export ZSH_CUSTOM="$HOME/.config/oh-my-zsh/custom"
        ${lib.optionalString pkgs.stdenv.isLinux ''export LIBVIRT_DEFAULT_URI="qemu:///system"''}
        VI_MODE_SET_CURSOR=true
      '';
    };

    initContent = ''
      # Use Neovim as man-db's pager while keeping `man 2 write` as a normal
      # terminal command. man-db strips formatting on pipes unless this is set.
      export MAN_KEEP_FORMATTING=1
      export MANPAGER='nvim +Man!'
      export MANWIDTH=999

      # ---------------------------------------------------------
      # 1. KEY MAPPING FIXES
      # ---------------------------------------------------------

      # Alt+Backspace -> Delete Word (Standard ^H mapping)
      bindkey '^H' backward-kill-word

      # Standard Backspace -> Delete Character
      bindkey '^?' backward-delete-char 

      # Cmd+Left/Right -> Jump to Start/End of Line (mapped to Home/End)
      bindkey '^[[H' beginning-of-line
      bindkey '^[[F' end-of-line

      # ---------------------------------------------------------
      # 2. CLEAR SCREEN FIXES (Ctrl+F & Ctrl+L)
      # ---------------------------------------------------------

      # [RESTORED] Ctrl+F to Clear Screen
      # We bind this in ALL modes to prevent the "^F" print error.
      bindkey '^f'      clear-screen
      bindkey -M viins '^f' clear-screen
      bindkey -M vicmd '^f' clear-screen

      # Ctrl+L (Standard Clear) - kept just in case
      bindkey '^L'      clear-screen
      bindkey -M viins '^L' clear-screen
      bindkey -M vicmd '^L' clear-screen

      # ---------------------------------------------------------
      # 3. VI MODE & SYSTEM FIXES
      # ---------------------------------------------------------

      # Fix Ctrl+C (Interrupt) in Command Mode
      bindkey -M vicmd '^C' send-break

      # "jk" to Escape
      bindkey -M viins 'jk' vi-cmd-mode

      # ---------------------------------------------------------
      # 4. FZF CONFIGURATION
      # ---------------------------------------------------------
      if type fzf &>/dev/null; then
        export FZF_DEFAULT_COMMAND='fd --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
        
        _fzf_preview_cmd='
          if [ -d {} ]; then eza -lT --level=2 --icons=always --color=always {} | head -200
          else bat --style=numbers --color=always --line-range :200 {} 2>/dev/null
          fi'
          
        export FZF_DEFAULT_OPTS="--border --layout=reverse --preview-window=right:60%:wrap --preview '$_fzf_preview_cmd'"
      fi

      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

      # ---------------------------------------------------------
      # 5. ALIASES (RESTORED)
      # ---------------------------------------------------------
      function re() {
        pushd ~/nixcfg > /dev/null && ${linuxRebuild} && popd > /dev/null
      }

      function ocu() {
        local original_dir="$PWD"
        cd ~/nixcfg || return 1

        if nix flake update custom-packages/opencode-flake; then
          echo "Rebuilding..."
          re
        else
          echo "Opencode update failed"
        fi

        cd "$original_dir"
      }

      ${linuxUpdateHelpers}

      alias lgit="lazygit"
      alias p="pnpm"
      alias cm="cd ~/Developer/Work/UP/mono/"
      alias cs="cd ~/Developer/sandbox/"
      alias sa="cd ~/Developer/OS/Sealant/"
      alias cn="cd ~/nixcfg/"
      alias mc="mc-prism"
      alias c="cursor ."
      alias n="nvim"

      if type eza &>/dev/null; then
        alias l="eza --icons=always"
        alias la="eza -a --icons=always"
        alias lh="eza -ad --icons=always .*"
        alias ll="eza -lg --icons=always"
        alias lla="eza -lag --icons=always"
        alias llh="eza -lagd --icons=always .*"
        alias ls="eza --icons=always"
        alias lt2="eza -lTg --level=2 --icons=always"
        alias lt3="eza -lTg --level=3 --icons=always"
        alias lt4="eza -lTg --level=4 --icons=always"
        alias lt="eza -lTg --icons=always"
        alias lta2="eza -lTag --level=2 --icons=always"
        alias lta3="eza -lTag --level=3 --icons=always"
        alias lta4="eza -lTag --level=4 --icons=always"
        alias lta="eza -lTag --icons=always"
      fi
    '';
  };

  home.file.".config/oh-my-zsh/custom/themes/powerlevel10k".source =
    "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k";

  home.file.".p10k.zsh".source = ./p10k/.p10k.zsh;

  home.packages = with pkgs; [
    zsh-powerlevel10k
    fzf
  ];
}
