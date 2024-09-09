-- buffers.lua
--
-- Convenience module at the base of the import tree.
-- Container for all buffer-specific data.

local buffers = {
  ---@type {[string]: BufferData}
  buffers_to_data = {},
}

---@param buffer_id integer
function buffers.prepare_new(buffer_id)
  buffers.buffers_to_data[tostring(buffer_id)] = {
    nodes = {},
    node_id_to_extmarks = {},
  }
end

return buffers
