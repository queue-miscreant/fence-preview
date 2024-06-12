local pipeline = require "fence_preview.pipeline"
local latex = require "fence_preview.latex"

local generate_content = {}


---@param node node
function generate_content.refold_node(node)
  if node.params == nil or node.params == vim.NIL or node.params.height == nil then return end

  -- delete all folds in the range
  local saved = vim.fn.winsaveview()
  pcall(function() vim.cmd(("normal %dGzD"):format(node.range[2] - 1)) end)
  vim.fn.winrestview(saved)

  local height = math.max(node.params.height, fence_preview.minimum_height)
  if height < node.range[2] - node.range[1] + 1 then
    -- add fold to the proper height
    vim.cmd(("%d,%dfold"):format(node.range[1] + height - 2, node.range[2] - 1))
  end
end


---@type pipeline_stage
function generate_content.try_draw_extmark(args)
  local path = args.previous
  local node = args.node

  if vim.fn.filereadable(path) == 0 then return end

  vim.defer_fn(function()
    vim.api.nvim_buf_call(node.buffer, function()
      if vim.b.draw_number ~= args.draw_number then return end

      generate_content.refold_node(node)

      -- Compare the node received against nodes in the current buffer
      for _, last_node in ipairs(fence_preview.last_nodes) do
        -- Try to reuse extmark
        local last_node_extmark = fence_preview.extmark_map[tostring(last_node.id)]
        if
          node.id == last_node.id
          and last_node_extmark ~= nil
        then
          if last_node.hash ~= node.hash then
            sixel_extmarks.change_content(last_node_extmark, path)
            sixel_extmarks.move(last_node_extmark, node.range[1] - 1, node.range[2] - 1)
            return
          end
        end
      end

      fence_preview.extmark_map[tostring(node.id)] = sixel_extmarks.create(node.range[1] - 1, node.range[2] - 1, path)
    end)
  end, 0)
end


---@param message string
---@param args pipeline_input
function generate_content.try_error_extmark(message, args)
  local node = args.node

  pipeline.log(message)
  pipeline.log(args)

  vim.defer_fn(function()
    vim.api.nvim_buf_call(node.buffer, function()
      pipeline.log(vim.b.draw_number, args.draw_number)
      if vim.b.draw_number ~= args.draw_number then return end

      -- Compare the node received against nodes in the current buffer
      for _, last_node in ipairs(fence_preview.last_nodes) do
        -- Try to reuse extmark
        local last_node_extmark = fence_preview.extmark_map[tostring(last_node.id)]
        if
          node.id == last_node.id
          and last_node_extmark ~= nil
        then
          sixel_extmarks.set_extmark_error(last_node_extmark, message)
          sixel_extmarks.move(last_node_extmark, node.range[1] - 1, node.range[2] - 1)
          return
        end
      end

      fence_preview.extmark_map[tostring(node.id)] = sixel_extmarks.create_error(node.range[1] - 1, node.range[2] - 1, message)
    end)
  end, 0)
end


---@type {[string]: fun(params: fence_params): pipeline_stage[] }

-- TODO: versions for filenames only

pipeline.add_runner("latex", function(_)
  return {
    latex.write_tex,
    latex.generate_dvi_from_latex,
    latex.generate_svg_from_dvi,
    latex.rasterize,
    generate_content.try_draw_extmark
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
    latex.gnuplot_to_png,
    generate_content.try_draw_extmark
  }
end)


pipeline.add_runner("python", function(params)
  local ret = {
    latex.run_python
  }

  if vim.list_contains(params.others, "math") then
    -- Chain into math pipeline
    params["math"] = nil
    local math_pipeline = pipeline.runners.math(params)
    vim.list_extend(ret, math_pipeline)
  elseif vim.list_contains(params.others, "latex") then
    -- Chain into LaTeX pipeline
    params["latex"] = nil
    local latex_pipeline = pipeline.runners.latex(params)
    vim.list_extend(ret, latex_pipeline)
  elseif vim.list_contains(params.others, "image") then
    -- Display image
    table.insert(ret, generate_content.try_draw_extmark)
  else
    -- TODO
  end

  return ret
end)


---@type pipeline_stage
local function read_file(args, callback, error_callback)
  local path = args.previous --[[@as path]]

  local file = io.open(args.previous)
  if file == nil then
    error_callback(("Could not read file `%s`"):format(path))
    return
  end

  local content = file:read("a")
  file:close()

  callback(vim.split(content, "\n"))
end


---@param node file_node
---@return pipeline_stage[] | nil
local function extension_to_stages(node)
  local _, extension = (vim.fs.basename(node.filename)):match("([^.]*)%.?(%w*)$")
  if extension == nil then return nil end

  if extension == "plt" then -- gnuplot
    return {
      read_file,
      latex.gnuplot_to_png,
      generate_content.try_draw_extmark
    }
  elseif extension == "tex" then -- LaTeX
    return {
      latex.generate_dvi_from_latex,
      latex.generate_svg_from_dvi,
      latex.rasterize,
      generate_content.try_draw_extmark
    }
  else
    return { generate_content.try_draw_extmark }
  end

end


---@param nodes node[]
function generate_content.pipe_nodes(nodes, draw_number)
  for _, node in pairs(nodes) do
    ---@type pipeline_stage[] | nil
    local stages = nil
    ---@type string[] | string
    local value = nil
    if node.type == "file" then
      ---@cast node file_node
      stages = extension_to_stages(node)
      value = vim.fs.normalize(node.filename) -- TODO
    else
      ---@cast node fence_node
      local stage_builder = pipeline.runners[node.params.filetype]
      if stage_builder == nil then goto continue end

      stages = stage_builder(node.params)
      value = node.content
    end

    if stages == nil then goto continue end

    pipeline.run(
      {
        previous = value,
        node = node,
        draw_number = draw_number
      },
      stages,
      generate_content.try_error_extmark
    )

    ::continue::
  end
end


return generate_content
