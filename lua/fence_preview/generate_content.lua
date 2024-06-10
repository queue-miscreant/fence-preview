local pipeline = require "fence_preview.pipeline"
local latex = require "fence_preview.latex"

local generate_content = {}

---@type {[string]: fun(params: fence_params): pipeline_stage[] }

-- TODO: versions for filenames only

pipeline.add_runner("latex", function(_)
  return {
    latex.write_tex,
    latex.generate_dvi_from_latex,
    latex.generate_svg_from_dvi,
    latex.rasterize
  }
end)

pipeline.add_runner("math", function(params)
  return {
    latex.add_math_preamble,
    unpack(pipeline.runners.latex(params)) ---@diagnostic disable-line
  }
end)

pipeline.add_runner("gnuplot", function(_)
  return {
    latex.gnuplot_to_png
  }
end)


pipeline.add_runner("python", function(params)
  local ret = {
    latex.run_python
  }

  if vim.list_contains(params.others, "math") then
    params["math"] = nil
    local math_pipeline = pipeline.runners.math(params)
    vim.list_extend(ret, math_pipeline)
  elseif vim.list_contains(params.others, "latex") then
    params["latex"] = nil
    local latex_pipeline = pipeline.runners.latex(params)
    vim.list_extend(ret, latex_pipeline)
  elseif vim.list_contains(params.others, "image") then
    -- TODO
  else
    -- TODO
  end
  table.insert(ret, function(data) print(vim.inspect(data)) end)

  return ret
end)


---@param nodes node[]
function generate_content.pipe_nodes(nodes)
  for _, node in pairs(nodes) do
    -- TODO: no support for extensions
    ---@type (fun(params: fence_params): pipeline_stage[])|nil
    local stage_builder = pipeline.runners[node.params.filetype]
    if stage_builder == nil then --[[ TODO ]] goto continue end

    pipeline.run(
      {
        previous = node.content,
        node = node
      },
      stage_builder(node.params)
    )

    ::continue::
  end
end


return generate_content
