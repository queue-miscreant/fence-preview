-- fence_preview.lua
--
-- Autocommands for building a list of processable content and asynchronously rendering
-- said content into extmarks.

local delimit = require "fence_preview.delimit"
local node_action = require "fence_preview.node_action"
local side_window = require "fence_preview.side_window"
local pipeline = require "fence_preview.pipeline"
local path = require "fence_preview.path"

if false then
  sixel_extmarks = {} ---@diagnostic disable-line
end

---@diagnostic disable-next-line
fence_preview = {
  ---@type integer
  minimum_height = 3,
  pipeline = pipeline,
  path = path,
}

vim.api.nvim_create_augroup("FencePreview", { clear = false })


---@param node node
---@param cursor_line integer
---@return boolean
local function cursor_in_node(node, cursor_line)
  -- Cursor is inside this node
  return node.range[1] < cursor_line and cursor_line < node.range[2]
end


---@param nodes node[]
---@param cursor_line integer
---@return node|nil
local function node_under_cursor(nodes, cursor_line)
  for _, node in ipairs(nodes) do
    -- Cursor is inside this node
    if (node.range[1] <= cursor_line and cursor_line < node.range[2]) then
      return node
    end
  end

  return nil
end

---@param node1 node
---@param node2 node
local function compare_nodes(node1, node2)
  -- Nodes have the same content
  return (
    node1.hash == node2.hash
  )
end

local function remove_unused_extmarks()
  -- Find all extmarks which are in the current extmark map
  local extmark_ids = {}
  for _, extmark_id in pairs(vim.b.extmark_map or {}) do
    extmark_ids[tostring(extmark_id)] = true
  end

  local current_images = {}
  -- Remove image extmarks which are not in the above map
  for _, extmark in pairs(sixel_extmarks.get(0, -1)) do
    current_images[tostring(extmark.id)] = true
    if extmark_ids[tostring(extmark.id)] == nil then
      sixel_extmarks.remove(extmark.id)
    end
  end

  -- Nodes no longer reference extmarks that do not exist
  for node_id, extmark_id in pairs(vim.b.extmark_map or {}) do
    if not current_images[tostring(extmark_id)] then
      vim.cmd(("unlet b:extmark_map[%d]"):format(node_id))
    end
  end
end


function fence_preview.reload()
  vim.b.draw_number = (vim.b.draw_number or 0) + 1
  ---@type integer
  local current_buffer = vim.api.nvim_get_current_buf()
  ---@type string[]
  local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, 0)

  local nodes = delimit.generate_nodes(current_lines, current_buffer)

  local no_process = {}

  -- Compare the new nodes with the previous nodes
  for _, prev_node in pairs(vim.b.last_nodes) do
    for _, node in pairs(nodes) do
      if
        vim.b.extmark_map[tostring(prev_node.id)] ~= nil
        and compare_nodes(node, prev_node)
      then
        no_process[tostring(node.id)] = true
        goto matched
      end
    end
    -- Node which no longer exists
    local extmark_id = vim.b.extmark_map[tostring(prev_node.id)]
    if extmark_id ~= nil then
      sixel_extmarks.remove(extmark_id)
    end
    vim.b.extmark_map[tostring(prev_node.id)] = nil

    ::matched::
  end

  -- Add the node under the cursor to the no process list
  vim.b.fence_preview_inside_node = nil
  local cursor_node = node_under_cursor(nodes, vim.fn.line("."))
  if cursor_node ~= nil then
    vim.b.fence_preview_inside_node = cursor_node.id
    no_process[tostring(cursor_node.id)] = true
  end

  remove_unused_extmarks()
  vim.wo.foldmethod = "manual"

  pipeline.pipe_nodes(
    vim.tbl_filter(
      function(node)
        return no_process[tostring(node.id)] == nil
      end,
      nodes
    ),
    vim.b.draw_number
  )

  vim.b.last_nodes = nodes
end


function fence_preview.show_logs()
  local new_buffer = vim.api.nvim_create_buf(0, 1)
  vim.api.nvim_buf_set_lines(
    new_buffer,
    0,
    -1,
    0,
    pipeline._logs
  )
  vim.api.nvim_open_win(
    new_buffer,
    true,
    {
      win = 0,
      split = "right"
    }
  )
end


function fence_preview.bind()
  if vim.b.fence_preview_bound_autocmds then return end

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
      callback = function() fence_preview.reload() end
    }
  )

  -- Push content in fences if the cursor has moved out of the way
  vim.api.nvim_create_autocmd(
    { "CursorMoved" },
    {
      group = "FencePreview",
      buffer = 0,
      callback = function()
        -- Do nothing if we did not hold off on processing a node due to cursor position
        if vim.b.fence_preview_inside_node == nil then return end

        -- We were in a node, so if the node under the cursor is the same one
        local current_node = node_under_cursor(vim.b.last_nodes, vim.fn.line("."))
        if
          current_node ~= nil
          and current_node.id == vim.b.fence_preview_inside_node
        then
          -- -- Attempt to re-fold the node if we're in normal mode
          -- if vim.fn.mode():sub(1, 1) ~= "n" then return end
          --
          -- local node = node_under_cursor(vim.b.last_nodes, vim.w.fence_preview_last_line or -1)
          -- local new_cursor = vim.fn.line(".")
          -- vim.w.fence_preview_last_line = new_cursor
          --
          -- if node ~= nil and not cursor_in_node(node, new_cursor) then
          --   node_action.refold(node)
          -- end
          return
        end

        vim.wo.foldmethod = "manual"
        pipeline.pipe_nodes(
          vim.tbl_filter(
            function(node) return node.id == vim.b.fence_preview_inside_node end,
            vim.b.last_nodes
          ),
          vim.b.draw_number
        )

        vim.b.fence_preview_inside_node = nil
      end
    }
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "OpenFence",
    function()
      if vim.fn.mode():sub(1, 1) ~= "n" then return end

      local node = node_under_cursor(vim.b.last_nodes, vim.fn.line("."))
      if node == nil then return end
      if node.type == "file" then return end

      side_window.enter_window(node) ---@diagnostic disable-line
    end,
    {}
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "FenceRefresh",
    function() fence_preview.reload() end,
    {}
  )

  vim.b.last_nodes = vim.empty_dict()
  vim.b.extmark_map = vim.empty_dict()
  vim.b.fence_preview_bound_autocmds = true

  fence_preview.reload()
end
