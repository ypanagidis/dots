{ config, ... }:

let
  # The unified repo layout: raw dotfiles live in dots/, this flake in nix/.
  # mkOutOfStoreSymlink keeps the live configs editable without a rebuild —
  # edits in the repo apply immediately, exactly like the Arch setup did.
  dots = "${config.home.homeDirectory}/Developer/Configs/dots";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";
in
{
  # Only configs that no home-manager module manages natively belong here.
  # ghostty/zsh/tmux/nvim/btop are owned by their nix modules; unifying those
  # with the dots versions is a deliberate per-app migration, not a bulk link.
  xdg.configFile = {
    "alacritty".source = link ".config/alacritty";
    "herdr".source = link ".config/herdr";
    "lazygit".source = link ".config/lazygit";
    "git".source = link ".config/git";
  };
}
