require("mini.surround").setup({
  -- Add custom surroundings to be used on top of builtin ones
  custom_surroundings = nil,

  -- Duration of highlight when calling `MiniSurround.highlight()`
  highlight_duration = 500,

  -- Module mappings. Use `''` to disable one.
  mappings = {
    add = "gsa",            -- Add surrounding in Normal and Visual modes
    delete = "gsd",         -- Delete surrounding
    find = "gsf",           -- Find surrounding (to the right)
    find_left = "gsF",      -- Find surrounding (to the left)
    highlight = "gsh",      -- Highlight surrounding
    replace = "gsr",        -- Replace surrounding
    update_n_lines = "gsn", -- Update `n_lines`

    suffix_last = "l",      -- Suffix to search with "prev" method
    suffix_next = "n",      -- Suffix to search with "next" method
  },

  -- Number of lines within which surrounding is searched
  n_lines = 20,

  -- Whether to respect selection type
  respect_selection_type = false,

  -- How to search for surrounding
  search_method = "cover",

  -- Whether to disable showing non-error feedback
  silent = false,
})

-- mini.pairs for auto brackets
require("mini.pairs").setup({
  -- In which modes mappings from this `config` should be created
  modes = { insert = true, command = false, terminal = false },

  -- Global mappings
  mappings = {
    ["("] = { action = "open", pair = "()", neigh_pattern = "[^\\]." },
    ["["] = { action = "open", pair = "[]", neigh_pattern = "[^\\]." },
    ["{"] = { action = "open", pair = "{}", neigh_pattern = "[^\\]." },

    [")"] = { action = "close", pair = "()", neigh_pattern = "[^\\]." },
    ["]"] = { action = "close", pair = "[]", neigh_pattern = "[^\\]." },
    ["}"] = { action = "close", pair = "{}", neigh_pattern = "[^\\]." },

    ['"'] = { action = "closeopen", pair = '""', neigh_pattern = "[^\\].", register = { cr = false } },
    ["'"] = { action = "closeopen", pair = "''", neigh_pattern = "[^%a\\].", register = { cr = false } },
    ["`"] = { action = "closeopen", pair = "``", neigh_pattern = "[^\\].", register = { cr = false } },
  },
})
