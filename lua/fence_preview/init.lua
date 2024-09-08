-- init.lua
--
-- Autocommands for building a list of processable content and asynchronously rendering
-- said content into extmarks.

require "fence_preview.stages"
local buffer_tree = require "fence_preview.buffer_tree"
local side_window = require "fence_preview.side_window"
local pipeline = require "fence_preview.pipeline"
local extmarks = require "fence_preview.extmarks"
local settings = require "fence_preview.settings"
local sixel_extmarks = require "sixel_extmarks"

local fence_preview = {
  ---TODO
  pipeline = pipeline,
  buffer_tree = buffer_tree,
  extmarks = extmarks,
  settings = settings,
}

vim.api.nvim_create_augroup("FencePreview", { clear = false })


function fence_preview.show_logs()
  local new_buffer = vim.api.nvim_create_buf(0, 1)
  local current_buffer = vim.api.nvim_get_current_buf()
  local logs = {}
  vim.tbl_map(
    ---@param node Node
    function(node)
      vim.list_extend(logs, node.logs)
    end,
    buffer_tree.buffers_to_data[tostring(current_buffer)].nodes
  )
  vim.api.nvim_buf_set_lines(new_buffer, 0, -1, 0, logs)
  vim.api.nvim_open_win(new_buffer, true, {
    win = 0,
    split = "right"
  })
end


function fence_preview.bind()
  local current_buffer = vim.api.nvim_get_current_buf()
  if fence_preview[tostring(current_buffer)] ~= nil then return end

  vim.cmd [[
    augroup ImageExtmarks
      autocmd! TextChanged,InsertLeave
    augroup END
  ]]

  -- Reload fences on text updated
  vim.api.nvim_create_autocmd(
    { "TextChanged", "InsertLeave" },
    {
      group = "FencePreview",
      buffer = 0,
      callback = function() buffer_tree.reload_buffer() end
    }
  )

  -- Push content in fences if the cursor has moved out of the way
  vim.api.nvim_create_autocmd(
    { "CursorMoved", "BufWrite" },
    {
      group = "FencePreview",
      buffer = 0,
      callback = function(e) buffer_tree.try_update_inside_node(e.event ~= "CursorMoved") end
    }
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "FenceOpen",
    function()
      if vim.fn.mode():sub(1, 1) ~= "n" then return end

      local node = buffer_tree.node_at_line(vim.fn.line("."))
      if node == nil then return end
      if node.type == "file" then return end

      side_window.enter_window(node) ---@diagnostic disable-line
    end,
    {}
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "FenceRefreshAll",
    function()
      buffer_tree.reload_buffer()
      sixel_extmarks.redraw()
    end,
    {}
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "FenceRefresh",
    function()
      local node = buffer_tree.node_at_line(vim.fn.line("."))
      if node == nil then return end
      if node.type == "file" then return end

      pipeline.pipe_node(node, true)
    end,
    {}
  )

  buffer_tree.prepare_new_buffer(current_buffer)
  buffer_tree.reload_buffer()
end

return fence_preview
