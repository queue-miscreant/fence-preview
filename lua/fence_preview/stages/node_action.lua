local buffer_tree = require "fence_preview.buffer_tree"
local extmarks = require "fence_preview.extmarks"

local node_action = {}


-- Attempt to create or set an image extmark at the node location
--
---@type PipelineStage
function node_action.try_draw_extmark(args)
  local image_path = args.previous --[[@as Path | string]]
  local node = args.node

  vim.defer_fn(function()
    vim.api.nvim_buf_call(node.buffer, function()
      -- Buffer has updated since the last time the pipeline was invoked
      -- This should fail silently
      if vim.b.fence_preview_draw_number ~= args.node.draw_number then return end

      -- Ensure node exists in buffer
      local buffer_data = buffer_tree.buffers_to_data[tostring(node.buffer)]
      if buffer_data == nil then return end

      extmarks.add_image(buffer_data, node, image_path)
    end)
  end, 0)
end


-- Attempt to create or set an extmark containing an error message over the node
--
---@param add_extmark fun(buffer_data: BufferData, node: Node, message: any)
---@return PipelineStage
local function text_extmark(add_extmark)
  return function(args)
    local message = args.previous
    local node = args.node

    vim.defer_fn(function()
      vim.api.nvim_buf_call(node.buffer, function()
        if vim.b.fence_preview_draw_number ~= args.node.draw_number then return end
        local buffer_data = buffer_tree.buffers_to_data[tostring(node.buffer)]
        if buffer_data == nil then return end

        add_extmark(buffer_data, node, message)
      end)
    end, 0)
  end
end

node_action.try_text_extmark = text_extmark(extmarks.add_text)
node_action.try_error_extmark = text_extmark(extmarks.add_error)

return node_action
