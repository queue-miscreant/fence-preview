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
  image_extmark_handler = (
    vim.g.image_extmarks_allow_virtual == 0
      and "sixel_virtual"
      or "sixel_inline"
  ),

  minimum_inline_fence_height = 3,
  default_virtual_file_height = 10,
  maximum_text_lines = 3,

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

local config = vim.deepcopy(default_config) or default_config

function config.load_globals(opts)
  -- Load the new options or global variables
  for option, default_value in pairs(default_config) do
    local global_value = vim.g["fence_preview_" .. option]
    local lazy_value = opts[option]
    if global_value ~= nil then
      config[option] = global_value
    elseif lazy_value ~= nil then
      config[option] = lazy_value
    end

    if config[option] == nil then
      config[option] = default_value
    end
  end
end

return config
