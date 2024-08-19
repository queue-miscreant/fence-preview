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
      node.params.height or (node.range[2] - node.range[1] + 1),
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
      -- Buffer has updated since the last time the pipeline was invoked
      -- This should fail silently
      if vim.b.fence_preview_draw_number ~= args.node.draw_number then return end

      -- Try making this path relative to this buffer's filename
      image_path = image_path == nil and {} or image_path:relative_to(vim.api.nvim_buf_get_name(0))
      -- TODO: alert error
      if image_path.exists == nil or not image_path:exists() then return end

      -- Ensure node exists in buffer
      local buffer_data = buffer_tree.buffers_to_data[tostring(node.buffer)]
      if buffer_data == nil then return end

      node_action.refold(node)

      -- Compare the node received against nodes in the current buffer
      for _, last_node in ipairs(buffer_data.nodes) do
        -- Try to reuse extmark
        local last_node_extmark = buffer_data.node_id_to_extmarks[tostring(last_node.id)]
        if
          node.id == last_node.id
          and last_node_extmark ~= nil
        then
          buffer_tree.remove_extmark(last_node_extmark)
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

        local new_extmark_id = sixel_extmarks.create_virtual(
          start_line - 1,
          height,
          image_path.path
        )
        buffer_data.node_id_to_extmarks[tostring(node.id)] = {
          id = new_extmark_id,
          type = "sixel",
        }
      else
        local new_extmark_id = sixel_extmarks.create(
          node.range[1] - 1,
          node.range[2] - 1,
          image_path.path
        )
        buffer_data.node_id_to_extmarks[tostring(node.id)] = {
          id = new_extmark_id,
          type = "sixel",
        }
      end
    end)
  end, 0)
end

-- Remove empty lines before and after a list of nonempty lines, then return a
-- list with at most target_length lines, trimming with an ellipsis if necessary.
--
---@param message string[]
---@param target_length integer
local function trim_to_line_count(message, target_length)
  local start = #message
  local end_ = 1
  for i = 1, #message do
    if message[i] ~= "" then
      start = i
      break
    end
  end

  for i = #message, 1, -1 do
    if message[i] ~= "" then
      end_ = i
      break
    end
  end

  if end_ - start + 1 > target_length then
    local ret = vim.list_slice(message, start, start + target_length - 1)
    table.insert(ret, "...")
    return ret
  end

  return vim.list_slice(message, start, end_)
end

-- Convert a generic table (or string or integer) to something that can be used as
-- an argument to `nvim_buf_set_extmark`.
--
---@param range [integer, integer] The range of the node this message belongs to
---@param message any The message to render as an extmark
---@param highlight string The highlight to use within the extmark
---@return virt_text_args|virt_lines_args, integer
local function message_to_extmark(range, message, highlight)
  ---@alias hlpair [string, string]
  ---@class virt_text_args
  ---@field virt_text hlpair[]
  ---@field virt_text_pos string

  ---@class virt_lines_args
  ---@field virt_lines hlpair[][]

  ---@type virt_text_args|virt_lines_args
  local extmark_args
  local start_line = range[1]
  if type(message) == "table" then
    if type(message[1]) == "string" then
      if #message == 1 then
        extmark_args = {
          virt_text = {{ tostring(message), highlight }},
          virt_text_pos = "eol",
        }
      else
        start_line = range[2]
        extmark_args = {
          virt_lines = vim.tbl_map(
            function(line)
              ---@type hlpair[]
              return {{ tostring(line), highlight }}
            end,
            trim_to_line_count(message, settings.maximum_text_lines)
          )
        }
      end
    else
      start_line = range[2]
      extmark_args = {
        virt_lines = vim.tbl_map(
          function(line)
            ---@type hlpair[]
            return {{ tostring(line), highlight }}
          end,
          trim_to_line_count(
            vim.split("\n", vim.inspect(message)),
            settings.maximum_text_lines
          )
        )
      }
    end
  else
    extmark_args = {
      virt_text = {{ tostring(message), highlight }},
      virt_text_pos = "eol",
    }
  end

  return extmark_args, start_line
end


-- Attempt to create or set an extmark containing an error message over the node
--
---@param highlight string
---@return pipeline_stage
local function text_extmark(highlight, extra_info)
  return function(args)
    local message = args.previous
    local node = args.node

    if extra_info then
      node:log_self()
    end

    vim.defer_fn(function()
      vim.api.nvim_buf_call(node.buffer, function()
        if vim.b.fence_preview_draw_number ~= args.node.draw_number then return end
        local buffer_data = buffer_tree.buffers_to_data[tostring(node.buffer)]
        if buffer_data == nil then return end

        -- Compare the node received against nodes in the current buffer
        for _, last_node in ipairs(buffer_data.nodes) do
          -- Try to reuse extmark
          local last_node_extmark = buffer_data.node_id_to_extmarks[tostring(last_node.id)]
          if
            node.id == last_node.id
            and last_node_extmark ~= nil
          then
            buffer_tree.remove_extmark(last_node_extmark)
            break
          end
        end

        local extmark_args, start_line = message_to_extmark(node.range, message, highlight)
        local new_extmark_id = vim.api.nvim_buf_set_extmark(
          0,
          buffer_tree.TEXT_NAMESPACE,
          start_line - 1,
          0,
          extmark_args
        )
        buffer_data.node_id_to_extmarks[tostring(node.id)] = {
          id = new_extmark_id,
          type = "text",
        }
        -- XXX: Workaround for images not being able to tell when `virt_lines` are added
        sixel_extmarks.redraw()
      end)
    end, 0)
  end
end

node_action.try_text_extmark = text_extmark("FencePreviewText")
node_action.try_error_extmark = text_extmark("FencePreviewError", true)

return node_action
