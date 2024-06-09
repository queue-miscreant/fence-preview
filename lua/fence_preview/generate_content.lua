local pipeline = require "fence_preview.pipeline"
local latex = require "fence_preview.latex"

local generate_content = {}

---@type {[string]: fun(params: fence_params): pipeline_stage[] }

pipeline.add_runner("latex", function(params)
  return {
    latex.generate_dvi_from_latex,
    latex.generate_svg_from_dvi
    -- TODO: rasterize
  }
end)

pipeline.add_runner("math", function(params)
  return {
    latex.write_math,
    unpack(pipeline.runners.latex(params)) ---@diagnostic disable-line
  }
end)

pipeline.add_runner("gnuplot", function(params)
  return {
    -- TODO: write to gnuplot file
    latex.generate_dvi_from_latex,
    latex.generate_svg_from_dvi
  }
end)


pipeline.add_runner("python", function(params)
  local ret = {
    -- TODO: python input
  }

  if params.others["math"] then
    params["math"] = nil
    local math_pipeline = pipeline.runners.math(params)
    table.move(math_pipeline, 1, #math_pipeline, #ret + 1, ret)
  elseif params.others["latex"] then
    params["latex"] = nil
    local latex_pipeline = pipeline.runners.latex(params)
    table.move(latex_pipeline, 1, #latex_pipeline, #ret + 1, ret)
  elseif params.others["image"] then
    -- TODO
  end

  return ret
end)

return generate_content
