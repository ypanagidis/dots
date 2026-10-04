{
  pkgs,
  lib,
  dotsLink,
  ...
}:

{
  # Neovim: the config is the shared dots/.config/nvim (lazy.nvim +
  # lazy-lock.json, same tree the Arch install symlinks). Nix declares the
  # editor and every external tool the config expects on PATH. The old
  # nix-managed lua tree lived next to this file; it was retired when the
  # dots/ copy became the single source of truth.
  xdg.configFile."nvim".source = dotsLink ".config/nvim";

  # Home Manager owns ~/.zshenv on NixOS, so the exports in the shared
  # dots/.config/zsh/.zshenv are not sourced here. Declare the editor in the
  # session environment so long-running tools such as Herdr inherit it too.
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.packages = with pkgs; [
    neovim

    # Needed by lazy.nvim (git fetches) and nvim-treesitter (grammar builds).
    git
    gcc
    tree-sitter

    # LSP servers
    # Classic TypeScript 5 owns `tsc`/`tsserver` (ts_ls compatibility).
    typescript_5
    typescript-language-server
    # nixpkgs `typescript` is now TypeScript 7 (the Go port) and only ships
    # `tsc`. Expose it as `tsgo`, which lsp.lua falls back to when a project
    # has no local node_modules/.bin/tsgo.
    (runCommand "tsgo" { } ''
      mkdir -p $out/bin
      ln -s ${lib.getExe' typescript "tsc"} $out/bin/tsgo
    '')
    oxlint
    tailwindcss-language-server
    gopls
    lua-language-server

    # Formatters
    prettierd
    prettier
    stylua
    nixfmt
    go
    gofumpt
    gotools
    golangci-lint
    delve

    # Picker / utility dependencies (snacks, telescope-style pickers)
    ripgrep
    fd
    lazygit
    oxfmt

    # Yazi file manager
    yazi
  ];
}
