local config = {
  minimum_inline_fence_height = 3,
  default_virtual_file_height = 10,
  maximum_text_lines = 3,

  preview_extensions = { ".png", ".jpg", ".jpeg" },

  latex = {
    math_start = [[
    \documentclass[20pt, preview]{standalone}
    \nonstopmode
    \usepackage{amsmath,amsfonts,amsthm}
    \usepackage{xcolor}
    %s
    \begin{document}
    %s
    \[]],
    math_end = [[
    \]
    \end{document}
    ]],
    force_mode = "", -- "dark" or "light" to use instead of vim.o.background
    extra_preamble = [[]],
    extra_document = [[]],
    extra_packages = {},
  }
}

return config
