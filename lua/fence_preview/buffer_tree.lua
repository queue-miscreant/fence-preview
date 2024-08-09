-- fence_preview.lua
--
-- Autocommands for building a list of processable content and asynchronously rendering
-- said content into extmarks.

local delimit = require "fence_preview.delimit"
local pipeline = require "fence_preview.pipeline"


---@class buffer_data
---@field nodes node[]
---@field node_id_to_extmark_id {[string]: integer}


local buffer_tree = {
  ---@type {[string]: buffer_data}
  buffers_to_data = {},
}


---@param node node
---@param cursor_line integer
---@return boolean
local function cursor_in_node(node, cursor_line)
  -- Cursor is inside this node
  return node.range[1] <= cursor_line and cursor_line < node.range[2]
end


---@param cursor_line integer
---@param nodes? node[]
---@return node|nil
function buffer_tree.node_at_line(cursor_line, nodes)
  if nodes == nil then
    local current_buffer = vim.api.nvim_get_current_buf()
    nodes = (buffer_tree.buffers_to_data[tostring(current_buffer)] or {}).nodes
  end
  if nodes == nil then return nil end

  for _, node in ipairs(nodes) do
    if cursor_in_node(node, cursor_line) then
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

---@param buffer_data buffer_data
local function remove_unused_extmarks(buffer_data)
  -- Find all extmarks which are in the current extmark map
  local extmark_ids = {}
  for _, extmark_id in pairs(buffer_data.node_id_to_extmark_id) do
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
  for node_id, extmark_id in pairs(buffer_data.node_id_to_extmark_id) do
    if not current_images[tostring(extmark_id)] then
      buffer_data.node_id_to_extmark_id[tostring(node_id)] = nil
    end
  end
end


function buffer_tree.reload_buffer()
  vim.b.fence_preview_draw_number = (vim.b.fence_preview_draw_number or 0) + 1
  ---@type integer
  local current_buffer = vim.api.nvim_get_current_buf()
  local buffer_data = buffer_tree.buffers_to_data[tostring(current_buffer)]
  if buffer_data == nil then return end
  ---@type string[]
  local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, 0)

  local nodes = delimit.generate_nodes(current_lines, current_buffer)

  local no_process = {}

  if buffer_data.nodes == nil then
    buffer_data.nodes = {}
  end
  local last_nodes = buffer_data.nodes

  -- Compare the new nodes with the previous nodes
  -- TODO this just needs to move stuff over, but we also need to `remove_unused`
  -- Consider refactoring
  for _, prev_node in pairs(last_nodes) do
    local extmark_id = buffer_data.node_id_to_extmark_id[tostring(prev_node.id)]
    for _, node in pairs(nodes) do
      if
        extmark_id ~= nil and compare_nodes(node, prev_node)
      then
        no_process[tostring(node.id)] = true
        goto matched
      end
    end
    -- Node which no longer exists
    if extmark_id ~= nil then
      sixel_extmarks.remove(extmark_id)
    end
    buffer_data.node_id_to_extmark_id[tostring(prev_node.id)] = nil

    ::matched::
  end

  -- Add the node under the cursor to the no process list
  vim.b.fence_preview_inside_node = nil
  local cursor_node = buffer_tree.node_at_line(vim.fn.line("."), nodes)
  if cursor_node ~= nil then
    vim.b.fence_preview_inside_node = cursor_node.id
    no_process[tostring(cursor_node.id)] = true
  end

  remove_unused_extmarks(buffer_data)
  vim.wo.foldmethod = "manual"

  buffer_data.nodes = nodes
  pipeline.pipe_nodes(
    vim.tbl_filter(
      function(node)
        return no_process[tostring(node.id)] == nil
      end,
      nodes
    ),
    vim.b.fence_preview_draw_number
  )
end

function buffer_tree.try_update_inside_node()
  -- Do nothing if we did not hold off on processing a node due to cursor position
  if vim.b.fence_preview_inside_node == nil then return end

  -- We were in a node, so if the node under the cursor is the same one
  local current_node = buffer_tree.node_at_line(vim.fn.line("."))
  if
    current_node ~= nil
    and current_node.id == vim.b.fence_preview_inside_node
  then
    return
  end

  local current_buffer = vim.api.nvim_get_current_buf()
  local buffer_data = buffer_tree.buffers_to_data[tostring(current_buffer)]
  if buffer_data == nil then return end

  vim.wo.foldmethod = "manual"
  pipeline.pipe_nodes(
    vim.tbl_filter(
      function(node) return node.id == vim.b.fence_preview_inside_node end,
      buffer_data.nodes
    ),
    vim.b.fence_preview_draw_number
  )

  vim.b.fence_preview_inside_node = nil
end


---@param current_buffer integer
function buffer_tree.prepare_new_buffer(current_buffer)
  buffer_tree.buffers_to_data[tostring(current_buffer)] = {
    nodes = {},
    node_id_to_extmark_id = {},
  }
end

return buffer_tree
