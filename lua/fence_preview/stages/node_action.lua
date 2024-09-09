local extmarks = require "fence_preview.extmarks"

local node_action = {}

-- Reenter main loop and add call extmark function on the node
--
---@param fn fun(node: Node, param: any)
---@return PipelineStage
local function add_extmark(fn)
  return function(args)
    local prev = args.previous
    local node = args.node

    vim.defer_fn(function()
      vim.api.nvim_buf_call(node.buffer, function()
        -- Buffer has updated since the last time the pipeline was invoked
        -- This should fail silently
        if vim.b.fence_preview_draw_number ~= args.node.draw_number then return end

        fn(node, prev)
      end)
    end, 0)
  end
end

node_action.try_draw_extmark = add_extmark(extmarks.add_image)
node_action.try_text_extmark = add_extmark(extmarks.add_text)
node_action.try_error_extmark = add_extmark(extmarks.add_error)

return node_action
