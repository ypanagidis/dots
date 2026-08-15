{ pkgs, dotsLink, ... }:

{
  # Tmux: package + plugins are declarative; the config is the shared
  # dots/.tmux.conf (same file the Arch install symlinks).
  home.packages = [ pkgs.tmux ];

  home.file.".tmux.conf".source = dotsLink ".tmux.conf";

  # Status-bar helper scripts (cpu/ram) referenced by the shared config.
  xdg.configFile."tmux".source = dotsLink ".config/tmux";

  # The shared .tmux.conf sources plugins from ~/.tmux/plugins/* only when
  # present (TPM on macOS). Here nix provides those files, so no TPM and no
  # network fetches.
  home.file.".tmux/plugins/vim-tmux-navigator/vim-tmux-navigator.tmux".source =
    pkgs.tmuxPlugins.vim-tmux-navigator.rtp;
  home.file.".tmux/plugins/tmux-yank/yank.tmux".source = pkgs.tmuxPlugins.yank.rtp;
}
