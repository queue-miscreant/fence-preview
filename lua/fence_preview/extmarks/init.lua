-- extmarks/init.lua
--
-- Wrappers providing extmark functionality.
-- It would be nice to support other image plugins in the future, so abstracting
-- this functionality here makes it easier for the plugin to work generally elsewhere.

local sixel_extmarks = require "sixel_extmarks"
local Path = require "fence_preview.polyfill.path"
local text_extmark = require "fence_preview.extmarks.text"

local extmarks = {
  ---@type {[string]: ExtmarkModule}
  image_handlers = {
    text = text_extmark,
    sixel_inline = require "fence_preview.extmarks.sixel_inline",
    sixel_virtual = require "fence_preview.extmarks.sixel_virtual"
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
--      A function for adding an extmark.
--      Should return a unique integer for this module.
--
-- remove(extmark_id: integer)
--      A function for removing an extmark.
--      `extmark_id` is the same value as returned by `add()`
--
-- iter_ids(): (fun(): integer?, integer?)
--      A function for retrieving all extmarks it is possible to `add()`
--      The second return value of the inner function is the same value as returned by `add()`
--      In other words, the following code must be valid:
--      ```
--        for _, extmark_id in module.iter_ids() do ... end
--      ```
--      Simply returning `pairs` or `ipairs` over a table will also work.
--
---@param module ExtmarkModule
function extmarks.install_image_handler(module)
  assert(module.add)
  assert(module.remove)
  assert(module.iter_ids)
  assert(module.name)
  extmarks.image_handlers[module.name] = module
end

-- TODO: move info dumps
---@param buffer_data BufferData
function extmarks._dump_image_extmarks(buffer_data)
  vim.print(
    vim.tbl_map(function(x) return {
      node_id = (function() for n, e in pairs(buffer_data.node_id_to_extmarks) do if tostring(e.id) == tostring(x.id) then return n end end end)(),
      height = x.height,
      start_row = x.start_row
    } end, sixel_extmarks.get(0, -1))
  )
end


-- Generically remove an extmark using the method provided by its module.
--
---@param extmark PipelineExtmark
function extmarks.remove_extmark(extmark)
  local module = extmarks.image_handlers[extmark.type]
  if module == nil then return end
  module.remove(extmark.id)
end


-- Clean up all extmarks added to the current buffer, but have been
-- desynced from the buffer contents.
--
---@param buffer_data BufferData
function extmarks.remove_all_unused(buffer_data)
  -- Sort extmarks by type
  ---@type {[string]: {[string]: boolean}}
  local extmarks_by_type = {}
  for _, extmark in pairs(buffer_data.node_id_to_extmarks) do
    local extmark_type = extmarks_by_type[extmark.type]
    if extmark_type == nil then
      extmark_type = {}
      extmarks_by_type[extmark.type] = extmark_type
    end

    extmark_type[tostring(extmark.id)] = true
  end

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


-- Try to remove an extmark which has already been added for a given node ID.
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
function extmarks.add_image(buffer_data, node, path)
  remove_existing(buffer_data, node.id)

  -- Get currently-loaded module
  local handler = vim.g.fence_preview_image_extmark_handler
  local module = extmarks.image_handlers[handler]
  if module == nil then
    return extmarks.add_error(buffer_data, node, "No extmark module found")
  end

  -- Convert string to Path; return error if invalid path object
  if type(path) == "string" then
    path = Path.new(path)
  elseif path.exists == nil then
    return extmarks.add_error(buffer_data, node, "Invalid path received")
  end
  -- Try making this path relative to the current buffer's filename
  path = path:relative_to(vim.api.nvim_buf_get_name(0))

  if not path:exists() then
    return extmarks.add_error(buffer_data, node, ("Could not find file '%s'"):format(path.path))
  end

  -- Call into the module
  local new_extmark_id = module.add(node, path)
  buffer_data.node_id_to_extmarks[tostring(node.id)] = {
    id = new_extmark_id,
    type = handler,
  }
end


-- Add a text extmark using a given highlight.
--
---@buffer_data BufferData
---@param node Node
---@param message any
---@param highlight string
function extmarks.add_text_generic(buffer_data, node, message, highlight)
  remove_existing(buffer_data, node.id)

  local new_extmark_id = text_extmark.add_text(node, message, highlight)
  buffer_data.node_id_to_extmarks[tostring(node.id)] = {
    id = new_extmark_id,
    type = text_extmark.name,
  }

  -- XXX: Workaround for images not being able to tell when `virt_lines` are added
  sixel_extmarks.redraw()
end


-- Add a text extmark using the default highlight.
--
---@buffer_data BufferData
---@param node Node
---@param message any
function extmarks.add_text(buffer_data, node, message)
  return extmarks.add_text_generic(buffer_data, node, message, "FencePreviewText")
end


-- Add an error extmark using the text backend. Logs the node beforehand.
--
---@buffer_data BufferData
---@param node Node
---@param message any
function extmarks.add_error(buffer_data, node, message)
  node:log_self()
  return extmarks.add_text_generic(buffer_data, node, message, "FencePreviewError")
end


return extmarks
