-- extmarks/init.lua
--
-- Wrappers providing extmark functionality.
-- It would be nice to support other image plugins in the future, so abstracting
-- this functionality here makes it easier for the plugin to work generally elsewhere.

local Path = require "fence_preview.polyfill.path"
local buffers = require "fence_preview.buffers"
local text_extmark = require "fence_preview.extmarks.text"

local extmarks = {
  ---@type {[string]: ExtmarkModule}
  image_handlers = {
    text = text_extmark,
    sixel_inline = require "fence_preview.extmarks.sixel_inline",
    sixel_virtual = require "fence_preview.extmarks.sixel_virtual",
  }
}

-- Add an extra image handler.
--
-- The module must have the following fields:
--
-- name :: string
--      The name of the module. Used to keep track of how an extmark was added.
--
-- add(node: Node, path: Path): integer
--      A function for adding an extmark to the current buffer.
--      Should return a unique integer for this module.
--
-- remove(extmark_id: integer)
--      A function for removing an extmark from the current buffer.
--      `extmark_id` is the same value as returned by `add()`
--
-- iter_ids(): (fun(): integer?, integer?)
--      A function for retrieving all extmarks that have been `add()`ed
--      The second return value of the inner function is the same value as returned by `add()`
--      In other words, the following code must be valid:
--      ```
--        for _, extmark_id in module.iter_ids() do ... end
--      ```
--      Simply returning `pairs` or `ipairs` over a table will also work.
--
-- Optionally, they can also include:
--
-- redraw(force?: boolean)
--      A function to redraw all visible images.
--
-- dump(extmark_id_to_node: {[string]: Node})
--      A function to log info about all known extmarks in the current buffer.
--      This is separate from `iter_ids` so that the plugin only needs to be concerned
--      with IDs, but additional information can be retrieved by developers.
--
--      A table mapping extmark IDs known by the plugin to their respective node is
--      passed as an argument.
--
---@param module ExtmarkModule
function extmarks.install_image_handler(module)
  assert(module.add)
  assert(module.remove)
  assert(module.iter_ids)
  assert(module.name)
  extmarks.image_handlers[module.name] = module
end


-- Generically remove an extmark from the current buffer using the method provided by its module.
--
---@param extmark PipelineExtmark
function extmarks.remove_extmark(extmark)
  local module = extmarks.image_handlers[extmark.type]
  if module == nil then return end
  module.remove(extmark.id)
end


-- Sort extmarks in a buffer by type (i.e., the module that added them)
-- Each entry of the returned table is a reverse-lookup of `extmark_id_to_node`,
-- which has indexed into `nodes`
--
---@param buffer_data BufferData
---@return {[string]: {[string]: Node}}
local function get_extmarks_by_type(buffer_data)
  ---@type {[string]: {[string]: Node}}
  local ret = {}
  for node_id, extmark in pairs(buffer_data.node_id_to_extmarks) do
    local extmark_type = ret[extmark.type]
    if extmark_type == nil then
      extmark_type = {}
      ret[extmark.type] = extmark_type
    end

    extmark_type[tostring(extmark.id)] = buffer_data.nodes[tonumber(node_id)]
  end

  return ret
end


-- Try to remove an extmark which has already been added for a given node ID.
-- TODO: reexamine
--
---@param buffer_data BufferData
---@param node_id integer
local function remove_existing(buffer_data, node_id)
  -- Compare the node received against nodes in the current buffer
  for _, last_node in ipairs(buffer_data.nodes) do
    -- Try to reuse extmark
    local last_node_extmark = buffer_data.node_id_to_extmarks[tostring(last_node.id)]
    if
      node_id == last_node.id
      and last_node_extmark ~= nil
    then
      extmarks.remove_extmark(last_node_extmark)
      break
    end
  end
end


-- Add a text extmark using the currently loaded image handler.
-- The current handler is specified in `g:fence_preview_image_extmark_handler`.
--
---@buffer_data BufferData
---@param node Node
---@param path Path | string
function extmarks._add_image(buffer_data, node, path)
  remove_existing(buffer_data, node.id)

  -- Get currently-loaded module
  local handler = vim.g.fence_preview_image_extmark_handler
  local module = extmarks.image_handlers[handler]
  if module == nil then
    return extmarks._add_error(buffer_data, node, "No extmark module found")
  end

  -- Convert string to Path; return error if invalid path object
  if type(path) == "string" then
    path = Path.new(path)
  elseif path.exists == nil then
    return extmarks._add_error(buffer_data, node, "Invalid path received")
  end
  -- Try making this path relative to the current buffer's filename
  path = path:relative_to(vim.api.nvim_buf_get_name(0))

  if not path:exists() then
    return extmarks._add_error(buffer_data, node, ("Could not find file '%s'"):format(path.path))
  end

  -- Call into the module
  local new_extmark_id = module.add(node, path)
  buffer_data.node_id_to_extmarks[tostring(node.id)] = {
    id = new_extmark_id,
    type = handler,
  }
end


-- Add a text extmark using the currently loaded image handler.
-- The current handler is specified in `g:fence_preview_image_extmark_handler`.
--
---@param node Node
---@param path Path | string
function extmarks.add_image(node, path)
  local current_buffer = vim.api.nvim_get_current_buf()
  local buffer_data = buffers.buffers_to_data[tostring(current_buffer)]
  if buffer_data == nil then return end

  extmarks._add_image(buffer_data, node, path)
end


-- Redraw all image extmarks according to the given buffer data.
--
---@param buffer_data BufferData
---@param force? boolean
function extmarks._redraw_all(buffer_data, force)
  local extmarks_by_type = get_extmarks_by_type(buffer_data)
  for module_name, _ in pairs(extmarks_by_type) do
    -- Find module and redraw
    module = extmarks.image_handlers[module_name]
    if module ~= nil and module.redraw ~= nil then
      module.redraw(force)
    end
  end
end


-- Redraw all image extmarks according to the given buffer data.
--
---@param force? boolean
function extmarks.redraw_all(force)
  local current_buffer = vim.api.nvim_get_current_buf()
  local buffer_data = buffers.buffers_to_data[tostring(current_buffer)]
  if buffer_data == nil then return end

  extmarks._redraw_all(buffer_data, force)
end


-- Dump data for all extmarks in the buffer, according to their type.
--
---@param buffer_data BufferData
---@param extmark_type? string
function extmarks._dump_all(buffer_data, extmark_type)
  local extmarks_by_type = get_extmarks_by_type(buffer_data)

  for module_name, extmark_id_to_node in pairs(extmarks_by_type) do
    -- Ignore module if filter parameter given
    if extmark_type == nil or module_name:find(extmark_type) then
      -- Find module and dump
      module = extmarks.image_handlers[module_name]
      if module ~= nil and module.dump ~= nil then
        module.dump(extmark_id_to_node)
      end
    end
  end
end


-- Dump data for all extmarks in the buffer, according to their type.
--
---@param extmark_type? string
function extmarks.dump_all(extmark_type)
  local current_buffer = vim.api.nvim_get_current_buf()
  local buffer_data = buffers.buffers_to_data[tostring(current_buffer)]
  if buffer_data == nil then return end

  extmarks._dump_all(buffer_data, extmark_type)
end


-- Add a text extmark using a given highlight.
--
---@param buffer_data BufferData
---@param node Node
---@param message any
---@param highlight string
function extmarks._add_text_generic(buffer_data, node, message, highlight)
  remove_existing(buffer_data, node.id)

  local new_extmark_id = text_extmark.add_text(node, message, highlight)
  buffer_data.node_id_to_extmarks[tostring(node.id)] = {
    id = new_extmark_id,
    type = text_extmark.name,
  }

  -- Contingency for extmarks being shifted around by virtual text
  extmarks._redraw_all(buffer_data)
end


-- Add a text extmark using a given highlight.
--
---@param node Node
---@param message any
---@param highlight string
function extmarks.add_text_generic(node, message, highlight)
  local current_buffer = vim.api.nvim_get_current_buf()
  local buffer_data = buffers.buffers_to_data[tostring(current_buffer)]
  if buffer_data == nil then return end

  extmarks._add_text_generic(buffer_data, node, message, highlight)
end


-- Add an error extmark using the text backend. Logs the node beforehand.
--
---@param buffer_data BufferData
---@param node Node
---@param message any
function extmarks._add_text(buffer_data, node, message)
  return extmarks._add_text_generic(buffer_data, node, message, "FencePreviewText")
end


-- Add a text extmark using the default highlight.
--
---@param node Node
---@param message any
function extmarks.add_text(node, message)
  return extmarks.add_text_generic(node, message, "FencePreviewText")
end


-- Add an error extmark using the text backend. Logs the node beforehand.
--
---@param buffer_data BufferData
---@param node Node
---@param message any
function extmarks._add_error(buffer_data, node, message)
  node:log_self()
  return extmarks._add_text_generic(buffer_data, node, message, "FencePreviewError")
end


-- Add an error extmark using the text backend. Logs the node beforehand.
--
---@param node Node
---@param message any
function extmarks.add_error(node, message)
  node:log_self()
  return extmarks.add_text_generic(node, message, "FencePreviewError")
end


-- Compare old node data with new node data.
-- Build a new `node_id_to_extmarks` table from new nodes with the same hashes as old ones.
-- Nonmatching extmarks are deleted.
--
---@param buffer_data BufferData
---@param new_nodes Node[]
---@return {[string]: PipelineExtmark}
local function reassign_extmarks(buffer_data, new_nodes)
  local last_nodes = buffer_data.nodes or {}
  ---@type {[string]: PipelineExtmark}
  local new_mapping = {}

  -- Compare the new nodes with the previous nodes
  for _, prev_node in ipairs(last_nodes) do
    local extmark = buffer_data.node_id_to_extmarks[tostring(prev_node.id)]
    if extmark == nil then goto matched end
    -- Find a new node with a matching hash to this old node
    for _, node in ipairs(new_nodes) do
      if node:equals(prev_node) then
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


-- Clean up all extmarks added to the current buffer, but have been
-- desynced from the buffer contents.
--
---@param buffer_data BufferData
local function remove_all_unused(buffer_data)
  -- Sort extmarks by type
  local extmarks_by_type = get_extmarks_by_type(buffer_data)

  -- For each extmark module...
  for module_name, current_extmarks in pairs(extmarks_by_type) do
    local module = extmarks.image_handlers[module_name]
    if module == nil then goto continue end
    -- Remove extmarks retrieved by the module that are NOT in `node_id_to_extmarks`
    for _, extmark_id in module.iter_ids() do
      if current_extmarks[tostring(extmark_id)] == nil then
        module.remove(extmark_id)
      end
    end

    ::continue::
  end
end


-- Rebuild the correspondence between extmarks and nodes for the current buffer.
--
---@param new_nodes Node[]
---@return BufferData?
function extmarks.reassign_current_buffer(new_nodes)
  ---@type integer
  local current_buffer = vim.api.nvim_get_current_buf()
  local buffer_data = buffers.buffers_to_data[tostring(current_buffer)]
  if buffer_data == nil then return end

  -- Make the extmark map tables consistent
  buffer_data.node_id_to_extmarks = reassign_extmarks(buffer_data, new_nodes)
  buffer_data.nodes = new_nodes
  remove_all_unused(buffer_data)

  return buffer_data
end


return extmarks
