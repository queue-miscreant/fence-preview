local pipeline = require "fence_preview.pipeline"

local stages = {
  latex = require "fence_preview.stages.latex",
  gnuplot = require "fence_preview.stages.gnuplot",
  python = require "fence_preview.stages.python",
  node_action = require "fence_preview.stages.node_action",
}

-- Basic pipeline terminator: display an image
pipeline.define("display", {
  stages.node_action.try_draw_extmark
})

-- Special text handler
pipeline.define("text", {
  stages.node_action.try_text_extmark
})

-- Special error handler
pipeline.define("error", {
  stages.node_action.try_error_extmark
})

-- TeX file pipeline
pipeline.define(".tex", {
  stages.latex.check_document,
  stages.latex.generate_dvi_from_latex,
  stages.latex.generate_svg_from_dvi,
  -- latex.rasterize,
  "display"
})

-- TeX fence pipeline
pipeline.define("#latex", {
  stages.latex.write_tex,
  ".tex"
})

-- Math fence pipeline
pipeline.define("#math", {
  stages.latex.add_math_preamble,
  "#latex"
})

-- Gnuplot fence pipeline
pipeline.define("#gnuplot", {
  stages.gnuplot.gnuplot_to_png,
  "display"
})

-- Gnuplot file pipeline
pipeline.define(".plt", {
  stages.gnuplot.read_file,
  "#gnuplot"
})

-- Python fence pipeline
pipeline.define(
  "#python",
  {stages.python.run_python},
  true
)

return stages
