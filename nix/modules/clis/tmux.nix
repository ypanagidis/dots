{
  pkgs,
  ...
}:
{
  programs.tmux = {
    enable = true;

    # 1. CORE SETTINGS
    # ---------------------------------------------------------
    terminal = "tmux-256color";
    prefix = "C-s";
    mouse = true;
    baseIndex = 1;

    # 2. PLUGINS
    # ---------------------------------------------------------
    plugins = with pkgs; [
      tmuxPlugins.vim-tmux-navigator

      # [NEW] Tmux Yank (Restores "Select to Copy" inside Tmux)
      # Since Tmux hijacks the mouse, this plugin ensures that releasing the
      # mouse button copies text to the system clipboard.
      tmuxPlugins.yank

      # CPU and RAM usage plugins
      {
        plugin = tmuxPlugins.cpu;
        extraConfig = ''
          set -g @cpu_percentage_format "%3.0f%%"
          set -g @ram_percentage_format "%3.0f%%"
        '';
      }
    ];

    # 3. EXTRA CONFIGURATION
    # ---------------------------------------------------------
    extraConfig = ''
      # =========================================================
      # 0. PASSTHROUGH FOR LINKS & OSC SEQUENCES
      # =========================================================
      set -g allow-passthrough on
      set -ga terminal-features "*:hyperlinks"

      # =========================================================
      # 1. KEYBOARD FIXES
      # =========================================================
      set-window-option -g xterm-keys on
      set -s escape-time 0

      # [FIX] Alt+Backspace (keyd sends Ctrl+h)
      # vim-tmux-navigator usually hijacks Ctrl+h. We unbind it so
      # the signal passes through to Zsh to delete the word.
      unbind -n C-h

      # [FIX] Alt+Arrows (Force Passthrough)
      bind -n C-Left send-keys Escape "[1;5D"
      bind -n C-Right send-keys Escape "[1;5C"

      # =========================================================
      # 2. VISUALS & CURSOR
      # =========================================================
      set -ag terminal-overrides ",xterm-256color:RGB"
      set -ga terminal-overrides ',*:Ss=\E[%p1%d q:Se=\E[2 q'

      # Force transparent background (fixes theme conflict)
      set -g window-style 'bg=default'
      set -g window-active-style 'bg=default'
      set -g pane-border-style 'bg=default'
      set -g pane-active-border-style 'bg=default'

      # =========================================================
      # CYBERDREAM THEME - STATUS BAR
      # =========================================================
      # Cyberdream colors
      cyberdream_bg="#16181a"
      cyberdream_fg="#ffffff"
      cyberdream_blue="#5ea1ff"
      cyberdream_cyan="#5ef1ff"
      cyberdream_green="#5eff6c"
      cyberdream_purple="#bd5eff"
      cyberdream_pink="#ff5ea0"
      cyberdream_grey="#7b8496"
      cyberdream_bg_highlight="#3c4048"

      # Status bar styling
      set -g status-style "bg=default,fg=$cyberdream_fg"
      set -g status-left-length 100
      set -g status-right-length 100
      set -g status-position bottom
      set -g status-justify left

      # Left side: Session name
      set -g status-left "#[fg=$cyberdream_blue,bold] #S #[fg=$cyberdream_grey]│ "

      # Right side: Git branch (if in git repo), CPU, RAM, Time
      set -g status-right "#[fg=$cyberdream_grey]#(cd #{pane_current_path}; git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/^/ /' | sed 's/$/ │/')#[fg=$cyberdream_grey]CPU:#[fg=$cyberdream_green]#(iostat -c 1 2 | grep -A 1 'avg-cpu' | tail -1 | awk '{printf \"%.0f%%\", 100-$6}') #[fg=$cyberdream_grey]RAM:#[fg=$cyberdream_cyan]#(free -h | awk '/^Mem:/ {print $3\"/\"$2}') #[fg=$cyberdream_grey]│ #[fg=$cyberdream_purple]%H:%M #[fg=$cyberdream_grey]%a %d"

      # Window status
      set -g window-status-format "#[fg=$cyberdream_grey] #I:#W "
      set -g window-status-current-format "#[fg=$cyberdream_blue,bold] #I:#W "
      set -g window-status-separator ""

      # Pane borders
      set -g pane-border-style "fg=$cyberdream_bg_highlight"
      set -g pane-active-border-style "fg=$cyberdream_blue"

      # Messages
      set -g message-style "bg=$cyberdream_bg_highlight,fg=$cyberdream_cyan"
      set -g message-command-style "bg=$cyberdream_bg_highlight,fg=$cyberdream_cyan"

      # =========================================================
      # 3. PANE MANAGEMENT
      # =========================================================
      unbind %
      bind = split-window -h
      unbind '"'
      bind - split-window -v

      bind -r j resize-pane -D 5
      bind -r k resize-pane -U 5
      bind -r l resize-pane -R 5
      bind -r h resize-pane -L 5
      bind -r m resize-pane -Z

      # =========================================================
      # 4. SCROLLING & COPYING
      # =========================================================
      set-window-option -g mode-keys vi

      # Configure Yank to copy to clipboard on mouse release
      set -g @yank_action 'copy-pipe-and-cancel'

      bind u copy-mode        # Prefix + u
      bind v copy-mode        # Prefix + v
      bind -n S-PageUp copy-mode -u

      bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e'"

      bind-key -T copy-mode-vi v send-keys -X begin-selection
      # 'y' is handled by tmux-yank, but keep as fallback
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind-key -T copy-mode-vi C-u send-keys -X halfpage-up
      bind-key -T copy-mode-vi C-d send-keys -X halfpage-down
    '';
  };
}
