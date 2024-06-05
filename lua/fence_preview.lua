-- fence_preview.lua
--
-- Lua callbacks for the Python backend
-- Generally ensures that "fast" callbacks such as creating new extmarks
-- done without IPC overhead.

---@class old_node
---@field content string
---@field filetype string
---@field range [integer, integer]

local delimit = require "fence_preview/delimit"
local side_window = require "fence_preview/side_window"

if false then
  sixel_extmarks = {} ---@diagnostic disable-line
end

---@diagnostic disable-next-line
fence_preview = {
  ---@type old_node[]
  node_cache = {},
  ---@type parsing_node[]
  last_nodes = {}
}


---@return node|nil
local function cursor_in_node(nodes, cursor_line)
  for _, node in ipairs(fence_preview.last_nodes) do
    -- Cursor is inside this node
    if (node.start < cursor_line and cursor_line < node.end_) then
      return node
    end
  end

  return nil
end


---@param buffer integer
---@param path string
---@param node node
function fence_preview.try_draw_extmark(buffer, path, node)
  -- TODO: the node received should be compared against nodes in the current buffer
  vim.api.nvim_buf_call(buffer, function()
    sixel_extmarks.create(node.start - 1, node.end_ - 1, path)
  end)
end


function fence_preview.reload()
  ---@type integer
  local current_buffer = vim.api.nvim_get_current_buf()
  ---@type string[]
  local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, 0)

  local nodes = delimit.generate_nodes(current_lines)

  -- Cursor
  vim.b.fence_preview_inside_node = nil
  local cursor_node = cursor_in_node(nodes, vim.fn.line("."))
  if cursor_node ~= nil then
    vim.b.fence_preview_inside_node = cursor_node.id
  end

  -- Push external content to Python for running
  sixel_extmarks.remove_all()
  vim.fn.FenceAsyncGen(
    current_buffer,
    vim.tbl_filter(
      function(node) return node.id ~= vim.b.fence_preview_inside_node end,
      nodes
    )
  )

  fence_preview.last_nodes = nodes
end


function fence_preview.bind()
  vim.cmd [[
    augroup ImageExtmarks
      autocmd! TextChanged,InsertLeave
    augroup END
  ]]

  -- Reload fences on text updated
  vim.api.nvim_create_autocmd(
    { "TextChanged", "InsertLeave" },
    {
      buffer = 0,
      callback = function() fence_preview.reload() end
    }
  )

  -- Push content in fences if the cursor has moved out of the way
  vim.api.nvim_create_autocmd(
    { "CursorMoved" },
    {
      buffer = 0,
      callback = function()
        if vim.b.fence_preview_inside_node == nil then return end

        vim.fn.FenceAsyncGen(
          vim.api.nvim_get_current_buf(),
          vim.tbl_filter(
            function(node) return node.id == vim.b.fence_preview_inside_node end,
            fence_preview.last_nodes
          )
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
      local node = cursor_in_node(fence_preview.last_nodes, vim.fn.line("."))
      if node == nil then return end

      -- TODO: cook the node into the proper format
      side_window.enter_window(node)
    end,
    {}
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "FenceRefresh",
    function() fence_preview.reload() end,
    {}
  )
end
