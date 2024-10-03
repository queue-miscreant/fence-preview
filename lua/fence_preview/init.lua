-- init.lua
--
-- Autocommands for building a list of processable content and asynchronously rendering
-- said content into extmarks.

require "fence_preview.stages"
local buffers = require "fence_preview.buffers"
local update = require "fence_preview.update"
local side_window = require "fence_preview.side_window"
local pipeline = require "fence_preview.pipeline"
local extmarks = require "fence_preview.extmarks"
local settings = require "fence_preview.settings"

local fence_preview = {
  ---TODO
  pipeline = pipeline,
  buffers = buffers,
  update = update,
  extmarks = extmarks,
  settings = settings,
}

vim.api.nvim_create_augroup("FencePreview", { clear = false })

local function set_current_window_options()
  -- TODO: Only use manual folds for inline extmarks
  if
    vim.g.fence_preview_image_extmark_handler == "sixel_inline"
    or vim.g.fence_preview_image_extmark_handler == "sixel_virtual"
  then
    vim.wo.foldmethod = "manual"
  end
end


function fence_preview.show_logs()
  local new_buffer = vim.api.nvim_create_buf(0, 1)
  local current_buffer = vim.api.nvim_get_current_buf()
  local logs = {}
  vim.tbl_map(
    ---@param node Node
    function(node)
      vim.list_extend(logs, node.logs)
    end,
    buffers.buffers_to_data[tostring(current_buffer)].nodes
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
      callback = function() update.current_buffer() end
    }
  )

  -- Push content in fences if the cursor has moved out of the way
  vim.api.nvim_create_autocmd(
    { "CursorMoved", "BufWrite" },
    {
      group = "FencePreview",
      buffer = 0,
      callback = function(e) update.try_inside_node(e.event ~= "CursorMoved") end
    }
  )

  -- Set window-local options
  vim.api.nvim_create_autocmd(
    { "WinEnter" },
    {
      group = "FencePreview",
      buffer = 0,
      callback = function(e)
        if buffers[tostring(e.buffer)] == nil then return end
        set_current_window_options()
      end
    }
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "FenceOpen",
    function()
      if vim.fn.mode():sub(1, 1) ~= "n" then return end

      local node = buffers.node_at_line(vim.fn.line("."))
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
      update.current_buffer()
      extmarks.redraw_all()
    end,
    {}
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "FenceRefresh",
    function()
      local node = buffers.node_at_line(vim.fn.line("."))
      if node == nil then return end
      if node.type == "file" then return end

      pipeline.pipe_node(node, true)
    end,
    {}
  )

  buffers.prepare_new(current_buffer)
  update.current_buffer()
  set_current_window_options()
end

return fence_preview
