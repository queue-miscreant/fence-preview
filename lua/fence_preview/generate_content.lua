local pipeline = require "fence_preview.pipeline"
local latex = require "fence_preview.latex"

local generate_content = {}


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

  if vim.fn.filereadable(tostring(path)) == 0 then return end

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


---@type pipeline_stage
function generate_content.try_error_extmark(args)
  local message = args.previous
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

pipeline.add_runner("display", {
  generate_content.try_draw_extmark
})

pipeline.add_runner("error", {
  generate_content.try_error_extmark
})

pipeline.add_runner(".tex", {
  latex.write_tex,
  latex.generate_dvi_from_latex,
  latex.generate_svg_from_dvi,
  latex.rasterize,
  "display"
})

pipeline.add_runner("#latex", {
  latex.write_tex,
  ".tex"
})

pipeline.add_runner("#math", {
  latex.add_math_preamble,
  "#latex"
})

pipeline.add_runner("#gnuplot", {
  latex.gnuplot_to_png,
  "display"
})

pipeline.add_runner(".plt", {
  read_file,
  "#gnuplot"
})

pipeline.add_runner("#python", {
    latex.run_python
})


---@return pipeline_stage[] | nil
local function extension_to_stages(args, callback)
  local _, extension = (vim.fs.basename(args.node.filename)):match("([^.]*)%.?(%w*)$")
  if extension == nil then return nil end

  local try_get_pipeline = "." .. extension
  local stages = pipeline.runners[try_get_pipeline]
  -- Pipeline exists for extension
  if stages ~= nil then
    callback(args.previous, try_get_pipeline)
  else
    callback(args.previous, "display")
  end
end


pipeline.add_runner("extension", {
    extension_to_stages
})


---@param nodes node[]
function generate_content.pipe_nodes(nodes, draw_number)
  for _, node in pairs(nodes) do
    ---@type string
    local stage_name
    ---@type string[] | string
    local value = nil
    if node.type == "file" then
      ---@cast node file_node
      stage_name = "extension"
      value = vim.fs.normalize(node.filename) -- TODO
    else
      ---@cast node fence_node
      stage_name = "#" .. node.params.filetype
      value = node.content
    end

    pipeline.run(
      {
        previous = value,
        node = node,
        draw_number = draw_number
      },
      pipeline.runners[stage_name]
    )
  end
end


return generate_content
