local buffer_tree = require "fence_preview.buffer_tree"
local settings = require "fence_preview.settings"

local node_action = {}


-- Apply folds to a node if it has a preferred height.
--
---@param node node
function node_action.refold(node)
  if node.type == "file" then return end

  -- Delete all folds in the range
  -- The line given should always be folded by the below statements
  local saved = vim.fn.winsaveview()
  pcall(function()
    vim.cmd(("normal %dGzD"):format(node.range[2] - 1))
  end)
  vim.fn.winrestview(saved)

  local fold_start
  -- Leave the last line of the fold outside
  if vim.g.fence_preview_use_virtual == 1 then
    -- Fold the entire content so that we can rely on the virtual lines
    fold_start = node.range[1]
  else
    local height = math.max(
      node.params.height or 0,
      settings.minimum_inline_fence_height
    )
    -- Nothing to fold
    if height >= node.range[2] - node.range[1] + 1 then
      return
    end
    fold_start = node.range[1] + height - 1 - 1
  end

  pcall(function()
    vim.cmd(("%d,%dfold"):format(
      fold_start,
      node.range[2] - 1
    ))
  end)
end


-- Attempt to create or set an image extmark at the node location
--
---@type pipeline_stage
function node_action.try_draw_extmark(args)
  local image_path = args.previous --[[@as path]]
  local node = args.node

  vim.defer_fn(function()
    vim.api.nvim_buf_call(node.buffer, function()
      -- Try making this path relative to this buffer's filename
      image_path = image_path == nil and {} or image_path:relative_to(vim.api.nvim_buf_get_name(0))
      -- TODO: alert error
      if image_path.exists == nil or not image_path:exists() then return end

      -- Buffer has updated since the last time the pipeline was invoked
      -- This should fail silently
      if vim.b.fence_preview_draw_number ~= args.node.draw_number then return end

      -- Ensure node exists in buffer
      local buffer_data = buffer_tree.buffers_to_data[tostring(node.buffer)]
      if buffer_data == nil then return end

      node_action.refold(node)

      -- Compare the node received against nodes in the current buffer
      for _, last_node in ipairs(buffer_data.nodes) do
        -- Try to reuse extmark
        local last_node_extmark = buffer_data.node_id_to_extmark_id[tostring(last_node.id)]
        if
          node.id == last_node.id
          and last_node_extmark ~= nil
        then
          sixel_extmarks.remove(last_node_extmark)
          break
        end
      end

      if vim.g.fence_preview_use_virtual == 1 then
        -- Place the extmark right after the fence
        local start_line = node.range[2]
        local height = node.range[2] - node.range[1] + 1
        if node.type == "file" then
          -- Place the extmark right below the image
          start_line = node.range[1]
          height = settings.default_virtual_file_height
        end
        if node.params.height ~= nil then
          height = node.params.height
        end

        buffer_data.node_id_to_extmark_id[tostring(node.id)] = sixel_extmarks.create_virtual(
          start_line - 1,
          height,
          image_path.path
        )
      else
        buffer_data.node_id_to_extmark_id[tostring(node.id)] = sixel_extmarks.create(
          node.range[1] - 1,
          node.range[2] - 1,
          image_path.path
        )
      end
    end)
  end, 0)
end


-- Attempt to create or set an extmark containing an error message over the node
--
---@type pipeline_stage
function node_action.try_error_extmark(args)
  local message = args.previous
  local node = args.node

  args.node:log(message)
  args.node:log(args)

  vim.defer_fn(function()
    vim.api.nvim_buf_call(node.buffer, function()
      args.node:log(vim.b.fence_preview_draw_number, args.node.draw_number)
      if vim.b.fence_preview_draw_number ~= args.node.draw_number then return end
      local buffer_data = buffer_tree.buffers_to_data[tostring(node.buffer)]
      if buffer_data == nil then return end

      -- Compare the node received against nodes in the current buffer
      for _, last_node in ipairs(buffer_data.nodes) do
        -- Try to reuse extmark
        local last_node_extmark = buffer_data.node_id_to_extmark_id[tostring(last_node.id)]
        if
          node.id == last_node.id
          and last_node_extmark ~= nil
        then
          sixel_extmarks.set_extmark_error(last_node_extmark, tostring(message))
          sixel_extmarks.move(last_node_extmark, node.range[1] - 1, node.range[2] - 1)
          return
        end
      end

      buffer_data.node_id_to_extmark_id[tostring(node.id)] = sixel_extmarks.create_error(
        node.range[1] - 1,
        node.range[2] - 1,
        tostring(message)
      )
    end)
  end, 0)
end

return node_action
