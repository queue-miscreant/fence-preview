local latex_math_start = [[
\documentclass[20pt, preview]{standalone}
\nonstopmode
\usepackage{amsmath,amsfonts,amsthm}
\usepackage{xcolor}
%s
\begin{document}
%s
\[]]
local latex_math_end = [[
\]
\end{document}
]]

local default_config = {
  -- Can use virtual extmarks instead of inline ones
  image_extmark_handler = "sixel_virtual",

  minimum_inline_fence_height = 3,
  default_virtual_file_height = 10,
  maximum_text_lines = 3,

  refresh_on_remove = true,

  preview_extensions = { ".png", ".jpg", ".jpeg" },

  latex = {
    math_start = latex_math_start,
    math_end = latex_math_end,
    force_mode = "", -- "dark" or "light" to use instead of vim.o.background
    extra_preamble = [[]],
    extra_document = [[]],
    extra_packages = {},
  }
}

-- Configuration settings which can be partially updated from user config
local table_configs = { "latex" }
local GLOBAL_PREFIX = "fence_preview_"

-- Start with defaults
local config = vim.deepcopy(default_config) or default_config

-- Additional updates to config
local function update_config()
  -- Set the handler for inline extmarks if we don't allow virtual ones
  local ok, image_extmarks_config = pcall(function() return require("sixel_extmarks.config") end)

  if not ok or not image_extmarks_config.allow_virtual then
    config.image_extmark_handler = "sixel_inline"
  end

  -- Attempting to retrieve an option's value inside a pipeline requires
  -- being synchronous with vim
  if config.latex.force_mode == "" then
    config.latex.force_mode = vim.o.background
  end
end

-- Load options from global variables and argument options
function config.load_globals(opts)
  -- Load the new options or global variables
  for option, default_value in pairs(default_config) do
    local global_value = vim.g[GLOBAL_PREFIX .. option]
    -- Convert Vim global from truthy number to boolean
    if type(global_value) == "number" and type(default_value) == "boolean" then
      global_value = global_value ~= 0
    end
    local lazy_value = opts[option]

    if global_value ~= nil then
      config[option] = global_value
    -- Only set lazy-configured options when table_configs
    elseif lazy_value ~= nil and table_configs[option] == nil then
      config[option] = lazy_value
    end

    if config[option] == nil then
      config[option] = vim.deepcopy(default_value)
    end
  end

  -- Load tableized options
  for _, option in ipairs(table_configs) do
    ---@diagnostic disable-next-line
    for suboption, _ in pairs(default_config[option] or {}) do
      local global_value = vim.g[GLOBAL_PREFIX .. option .. "_" .. suboption]
      -- Convert Vim global from truthy number to boolean
      if type(global_value) == "number" and type(default_config[option][suboption]) == "boolean" then
        global_value = global_value ~= 0
      end
      local lazy_value = (opts[option] or {})[suboption]

      if global_value ~= nil then
        config[option][suboption] = global_value
      end
      if lazy_value ~= nil then
        config[option][suboption] = lazy_value
      end
    end
  end

  update_config()
end

return config
