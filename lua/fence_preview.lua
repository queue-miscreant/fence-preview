-- fence_preview.lua
--
-- Lua callbacks for the Python backend
-- Generally ensures that "fast" callbacks such as creating new extmarks
-- done without IPC overhead.

local delimit = require "fence_preview/delimit"
local side_window = require "fence_preview/side_window"
local pipeline = require "fence_preview.pipeline"
local generate_content = require "fence_preview.generate_content"

if false then
  sixel_extmarks = {} ---@diagnostic disable-line
end

---@diagnostic disable-next-line
fence_preview = {
  -- TODO: move these to buffer-local
  ---@type node[]
  last_nodes = {},
  ---@type {[string]: integer}
  extmark_map = {},
  ---@type integer
  minimum_height = 3,
  pipeline = pipeline
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
    if (node.range[1] < cursor_line and cursor_line < node.range[2]) then
      return node
    end
  end

  return nil
end


---@param node node
local function refold_node(node)
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

---@param buffer integer
---@param path string
---@param node node
function fence_preview.try_draw_extmark(buffer, path, node, draw_number)
  vim.api.nvim_buf_call(buffer, function()
    if vim.b.draw_number ~= draw_number then return end

    refold_node(node)

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
          sixel_extmarks.move(last_node_extmark, node.range[1] - 1, node.range[2] - 1, path)
          return
        else
          sixel_extmarks.remove(last_node_extmark)
          break
        end
      end
    end

    fence_preview.extmark_map[tostring(node.id)] = sixel_extmarks.create(node.range[1] - 1, node.range[2] - 1, path)
  end)
end


function fence_preview.reload()
  vim.b.draw_number = (vim.b.draw_number or 0) + 1
  ---@type integer
  local current_buffer = vim.api.nvim_get_current_buf()
  ---@type string[]
  local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, 0)

  local nodes = delimit.generate_nodes(current_lines)

  -- Cursor
  vim.b.fence_preview_inside_node = nil
  local cursor_node = node_under_cursor(nodes, vim.fn.line("."))
  if cursor_node ~= nil then
    vim.b.fence_preview_inside_node = cursor_node.id
  end

  vim.wo.foldmethod = "manual"

  -- Push external content to Python for running
  sixel_extmarks.remove_all()
  vim.fn.FenceAsyncGen(
    current_buffer,
    vim.tbl_filter(
      function(node) return node.id ~= vim.b.fence_preview_inside_node end,
      nodes
    ),
    vim.b.draw_number
  )

  fence_preview.last_nodes = nodes
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
        if vim.b.fence_preview_inside_node == nil then
          -- Attempt to re-fold the node if we're in normal mode
          if vim.fn.mode():sub(1, 1) ~= "n" then return end

          local node = node_under_cursor(fence_preview.last_nodes, vim.w.fence_preview_last_line or -1)
          local new_cursor = vim.fn.line(".")
          vim.w.fence_preview_last_line = new_cursor

          if node ~= nil and not cursor_in_node(node, new_cursor) then
            refold_node(node)
          end
          return
        end

        vim.wo.foldmethod = "manual"

        vim.fn.FenceAsyncGen(
          vim.api.nvim_get_current_buf(),
          vim.tbl_filter(
            function(node) return node.id == vim.b.fence_preview_inside_node end,
            fence_preview.last_nodes
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

      local node = node_under_cursor(fence_preview.last_nodes, vim.fn.line("."))
      if node == nil then return end
      if node.type == "file" then return end

      -- TODO: cook the node into the proper format
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

  vim.b.fence_preview_bound_autocmds = true
end
