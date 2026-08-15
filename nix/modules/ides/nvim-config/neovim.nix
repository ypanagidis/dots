{ pkgs, dotsLink, ... }:

{
  # Neovim: the config is the shared dots/.config/nvim (lazy.nvim +
  # lazy-lock.json, same tree the Arch install symlinks). Nix declares the
  # editor and every external tool the config expects on PATH. The old
  # nix-managed lua tree lived next to this file; it was retired when the
  # dots/ copy became the single source of truth.
  xdg.configFile."nvim".source = dotsLink ".config/nvim";

  home.packages = with pkgs; [
    neovim

    # Needed by lazy.nvim (git fetches) and nvim-treesitter (grammar builds).
    git
    gcc

    # LSP servers
    typescript
    typescript-language-server
    tsgo # TypeScript 7 native compiler
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
