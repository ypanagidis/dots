{ pkgs, ... }:

{
  imports = [
    ./tmux.nix
    ./btop
    ./shell
    ./herdr.nix
  ];

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    git = {
      enable = true;
      settings = {
        user.name = "Yiannis Panagidis";
        user.email = "ypanagidis@gmail.com";
        init.defaultBranch = "main";
        credential."https://github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
        credential."https://gist.github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
      };
    };
    eza.enable = true;
    fzf.enable = true;
    lazygit.enable = true;
    gh.enable = true;
    bat.enable = true;
    yazi = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        manager = {
          show_hidden = true;
        };
      };
    };
  };

  # User-facing CLI tools that are not provided by a richer HM program module.
  home.packages = with pkgs; [
    fastfetch
    # Clipboard CLI — also what Claude Code and other TUIs use to read/write
    # image clipboard content under Wayland.
    wl-clipboard
    # xdotool-for-KWin; kde-ctx uses it to find/activate context windows.
    kdotool
  ];
}
