{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;

    initLua =
      builtins.readFile ./nvim/lua/options.lua + builtins.readFile ./nvim/lua/keymaps.lua;

    plugins = with pkgs.vimPlugins; [
      # LSP
      {
        plugin = nvim-lspconfig;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/lsp.lua;
      }

      # LSP progress indicator
      {
        plugin = fidget-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/fidget.lua;
      }

      # Formatting
      {
        plugin = conform-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/conform.lua;
      }

      # Completion
      {
        plugin = blink-cmp;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/blink.lua;
      }

      # Treesitter
      {
        plugin = pkgs.vimPlugins.nvim-treesitter.withAllGrammars;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/treesitter.lua;
      }

      # Treesitter context (sticky function/class header)
      {
        plugin = nvim-treesitter-context;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/treesitter-context.lua;
      }

      # Telescope (commented out - using Snacks picker instead)
      # plenary-nvim
      # {
      #   plugin = telescope-nvim;
      #   type = "lua";
      #   config = builtins.readFile ./nvim/lua/plugins/telescope.lua;
      # }

      # Snacks (utilities)
      {
        plugin = snacks-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/snacks.lua;
      }

      # Noice (better UI)
      nui-nvim
      nvim-notify
      {
        plugin = noice-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/noice.lua;
      }

      # Mini (surround + autopairs)
      {
        plugin = mini-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/mini.lua;
      }

      # Bufferline (tab bar)
      {
        plugin = bufferline-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/bufferline.lua;
      }

      # UI
      nvim-web-devicons
      {
        plugin = cyberdream-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/ui.lua;
      }
      lualine-nvim # loaded by ui.lua

      # Navigation
      {
        plugin = oil-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/oil.lua;
      }
      {
        plugin = yazi-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/yazi.lua;
      }
      {
        plugin = vim-tmux-navigator;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/tmux.lua;
      }
      # Diagnostics list
      {
        plugin = trouble-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/trouble.lua;
      }

      # Better TS/JSX comments
      {
        plugin = nvim-ts-context-commentstring;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/ts-comments.lua;
      }

      # AI Completion (Supermaven)
      {
        plugin = supermaven-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/supermaven.lua;
      }

      # Which-key (keybinding hints)
      {
        plugin = which-key-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/which-key.lua;
      }

      # Git signs in gutter
      {
        plugin = gitsigns-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/gitsigns.lua;
      }

      # VSCode-style git diff view
      {
        plugin = pkgs.vimPlugins.codediff-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/codediff.lua;
      }

      # TODO/FIXME highlighting
      {
        plugin = todo-comments-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/todo-comments.lua;
      }

      # Color code preview
      {
        plugin = nvim-colorizer-lua;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/colorizer.lua;
      }

      # Markdown rendered preview in buffer
      {
        plugin = render-markdown-nvim;
        type = "lua";
        config = builtins.readFile ./nvim/lua/plugins/markdown.lua;
      }

    ];

    extraPackages = with pkgs; [
      # LSP servers
      typescript
      typescript-language-server
      tsgo # TypeScript 7 native compiler
      oxlint
      tailwindcss-language-server
      gopls

      # Formatters
      prettierd
      prettier
      stylua
      nixfmt-rfc-style
      go
      gofumpt
      gotools
      golangci-lint
      delve

      # Snacks picker dependencies (also used by Telescope if re-enabled)
      ripgrep
      fd

      # Snacks dependencies
      lazygit
      oxfmt

      # Yazi file manager
      yazi
    ];

  };
}
