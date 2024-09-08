-- buffer_tree.lua
--
-- Functions for working with buffers recognized by the plugin.
-- Mostly provides buffer-wide utilities, such as corresponding a position with a node.

local delimit = require "fence_preview.delimit"
local pipeline = require "fence_preview.pipeline"
local extmarks = require "fence_preview.extmarks"


local buffer_tree = {
  ---@type {[string]: BufferData}
  buffers_to_data = {},
}


---@param cursor_line integer
---@param nodes? Node[]
---@return Node|nil
function buffer_tree.node_at_line(cursor_line, nodes)
  if nodes == nil then
    local current_buffer = vim.api.nvim_get_current_buf()
    nodes = (buffer_tree.buffers_to_data[tostring(current_buffer)] or {}).nodes
  end
  if nodes == nil then return nil end

  for _, node in ipairs(nodes) do
    if node:is_line_inside(cursor_line) then
      return node
    end
  end

  return nil
end

---@param node1 Node
---@param node2 Node
local function compare_nodes(node1, node2)
  -- Nodes have the same content
  return (
    node1.hash == node2.hash
  )
end

-- Compare old node data with new node data.
-- Build a new `node_id_to_extmarks` table from new nodes with the same hashes as old ones.
-- Nonmatching extmarks are deleted.
--
---@param nodes Node[]
---@param buffer_data BufferData
---@return {[string]: PipelineExtmark}
local function reassign_extmarks(nodes, buffer_data)
  local last_nodes = buffer_data.nodes or {}
  ---@type {[string]: PipelineExtmark}
  local new_mapping = {}

  -- Compare the new nodes with the previous nodes
  for _, prev_node in ipairs(last_nodes) do
    local extmark = buffer_data.node_id_to_extmarks[tostring(prev_node.id)]
    if extmark == nil then goto matched end
    -- Find a new node with a matching hash to this old node
    for _, node in ipairs(nodes) do
      if compare_nodes(node, prev_node) then
        new_mapping[tostring(node.id)] = buffer_data.node_id_to_extmarks[tostring(prev_node.id)]
        goto matched
      end
    end
    -- Node which no longer exists
    extmarks.remove_extmark(extmark)

    ::matched::
  end

  return new_mapping
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

  -- Make the extmark map tables consistent
  buffer_data.node_id_to_extmarks = reassign_extmarks(nodes, buffer_data)
  buffer_data.nodes = nodes
  extmarks.remove_all_unused(buffer_data)
  -- TODO: only for inline extmarks
  vim.wo.foldmethod = "manual"

  -- Make note of the current node under the cursor
  vim.b.fence_preview_inside_node = nil
  local cursor_node = buffer_tree.node_at_line(vim.fn.line("."), nodes)
  if cursor_node ~= nil then
    vim.b.fence_preview_inside_node = cursor_node.id
  end

  pipeline.pipe_nodes(
    vim.tbl_filter(
      ---@param node Node
      function(node)
        node.draw_number = vim.b.fence_preview_draw_number
        return buffer_data.node_id_to_extmarks[tostring(node.id)] == nil
          and node.id ~= vim.b.fence_preview_inside_node
      end,
      nodes
    )
  )
end

function buffer_tree.try_update_inside_node(ignore_cursor)
  -- Do nothing if we did not hold off on processing a node due to cursor position
  if vim.b.fence_preview_inside_node == nil then return end

  -- We were in a node, so if the node under the cursor is the same one
  local current_node = buffer_tree.node_at_line(vim.fn.line("."))
  if
    not ignore_cursor
    and current_node ~= nil
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
      ---@param node Node
      function(node)
        node.draw_number = vim.b.fence_preview_draw_number
        return node.id == vim.b.fence_preview_inside_node
      end,
      buffer_data.nodes
    )
  )

  vim.b.fence_preview_inside_node = nil
end


---@param current_buffer integer
function buffer_tree.prepare_new_buffer(current_buffer)
  buffer_tree.buffers_to_data[tostring(current_buffer)] = {
    nodes = {},
    node_id_to_extmarks = {},
  }
end

return buffer_tree
