{ config, ... }:

let
  # The unified repo layout: raw dotfiles live in dots/, this flake in nix/.
  # mkOutOfStoreSymlink keeps the live configs editable without a rebuild —
  # edits in the repo apply immediately, exactly like the Arch setup did.
  dots = "${config.home.homeDirectory}/Developer/Configs/dots";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";
in
{
  # Other modules (ghostty/tmux/nvim) reuse this helper to point their
  # xdg.configFile at the shared dots/ tree: packages stay declarative in
  # nix, the config content has one source of truth.
  _module.args.dotsLink = link;

  # Only configs with no dedicated module belong here. ghostty/tmux/nvim link
  # to dots/ from their own modules (via dotsLink); zsh/btop remain nix-native
  # for now — the dots zsh plugins are embedded git checkouts that a fresh
  # clone would not include.
  xdg.configFile = {
    "alacritty".source = link ".config/alacritty";
    "herdr".source = link ".config/herdr";
    "lazygit".source = link ".config/lazygit";
    # Only the ignore file — programs.git (clis/default.nix) owns
    # .config/git/config, so linking the whole dir collides with HM.
    "git/ignore".source = link ".config/git/ignore";
  };
}
