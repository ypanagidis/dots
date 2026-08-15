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
    typescript
    typescript-language-server
    # TypeScript 7 from nixpkgs; provides both tsgo and tsc. lowPrio so the
    # classic typescript package keeps owning `tsc` (ts_ls compatibility)
    # while `tsgo` comes from here — same split the old binary pin had.
    (lib.lowPrio typescript-go)
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
