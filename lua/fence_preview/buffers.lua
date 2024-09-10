-- buffers.lua
--
-- Convenience module at the base of the import tree.
-- Container for all buffer-specific data.

local buffers = {
  ---@type {[string]: BufferData}
  buffers_to_data = {},
}

-- Create entry for a buffer ID to be recognized by the plugin
--
---@param buffer_id integer
function buffers.prepare_new(buffer_id)
  buffers.buffers_to_data[tostring(buffer_id)] = {
    nodes = {},
    node_id_to_extmarks = {},
  }
end

-- Retrieves the node at a line number (1-based).
--
---@param line integer
---@param nodes? Node[] List of nodes to use. If absent, the node list for the current buffer will be used.
---@return Node?
function buffers.node_at_line(line, nodes)
  if nodes == nil then
    local current_buffer = vim.api.nvim_get_current_buf()
    nodes = (buffers.buffers_to_data[tostring(current_buffer)] or {}).nodes
  end
  if nodes == nil then return end

  for _, node in ipairs(nodes) do
    if node:is_line_inside(line) then
      return node
    end
  end
end

return buffers
