local pipeline = require "fence_preview.pipeline"
local latex = require "fence_preview.latex"

local node_action = {}

-- Read a file and pass its contents as a list of strings
--
---@type pipeline_stage
local function read_file(args, callback, error_callback)
  local file_path = args.previous --[[@as path]]

  local file = io.open(file_path.path)
  if file == nil then
    error_callback(("Could not read file `%s`"):format(file_path))
    return
  end

  local content = file:read("a")
  file:close()

  return vim.split(content, "\n")
end


-- Apply folds to a node if it has a preferred height.
--
---@param node node
function node_action.refold(node)
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


-- Attempt to create or set an image extmark over the node
--
---@type pipeline_stage
function node_action.try_draw_extmark(args)
  local image_path = args.previous --[[@as path]]
  local node = args.node

  if image_path.exists == nil or not image_path:exists() then return end

  vim.defer_fn(function()
    vim.api.nvim_buf_call(node.buffer, function()
      if vim.b.draw_number ~= args.draw_number then return end

      node_action.refold(node)

      -- Compare the node received against nodes in the current buffer
      for _, last_node in ipairs(fence_preview.last_nodes) do
        -- Try to reuse extmark
        local last_node_extmark = fence_preview.extmark_map[tostring(last_node.id)]
        if
          node.id == last_node.id
          and last_node_extmark ~= nil
        then
          if last_node.hash ~= node.hash then
            sixel_extmarks.change_content(last_node_extmark, image_path.path)
            sixel_extmarks.move(last_node_extmark, node.range[1] - 1, node.range[2] - 1)
            return
          end
        end
      end

      fence_preview.extmark_map[tostring(node.id)] = sixel_extmarks.create(node.range[1] - 1, node.range[2] - 1, image_path.path)
    end)
  end, 0)
end


-- Attempt to create or set an extmark containing an error message over the node
--
---@type pipeline_stage
function node_action.try_error_extmark(args)
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
          sixel_extmarks.set_extmark_error(last_node_extmark, tostring(message))
          sixel_extmarks.move(last_node_extmark, node.range[1] - 1, node.range[2] - 1)
          return
        end
      end

      fence_preview.extmark_map[tostring(node.id)] = sixel_extmarks.create_error(node.range[1] - 1, node.range[2] - 1, tostring(message))
    end)
  end, 0)
end

pipeline.define("display", {
  node_action.try_draw_extmark
})

pipeline.define("error", {
  node_action.try_error_extmark
})

pipeline.define(".tex", {
  latex.write_tex,
  latex.generate_dvi_from_latex,
  latex.generate_svg_from_dvi,
  -- latex.rasterize,
  "display"
})

pipeline.define("#latex", {
  latex.write_tex,
  ".tex"
})

pipeline.define("#math", {
  latex.add_math_preamble,
  "#latex"
})

pipeline.define("#gnuplot", {
  latex.gnuplot_to_png,
  "display"
})

pipeline.define(".plt", {
  read_file,
  "#gnuplot"
})

pipeline.define("#python", {
    latex.run_python
})

return node_action
