-- extmarks/sixel_inline.lua
--
-- Inline sixel extmark provider.
-- This is slightly-older `sixel_extmarks` functionality which renders
-- images on top of buffer contents, rather than adding virtual lines.

local loaded, sixel_extmarks = pcall(function() return require "sixel_extmarks" end)
if not loaded then
  vim.notify(
    "fence_preview: Missing dependency nvim_image_extmarks",
    vim.log.levels.ERROR
  )
  return {}
end
local config = require "fence_preview.config"

local sixel_inline = {
  name = "sixel_inline"
}

-- Apply folds to a node if it has a preferred height.
--
---@param node Node
local function refold(node)
  if node.type == "file" then return end

  -- Don't bother folding if the cursor is here
  if node:is_line_inside(vim.fn.line(".")) then return end

  -- Delete all folds in the range
  -- The line given should always be folded by the below statements
  local saved = vim.fn.winsaveview()
  pcall(function()
    vim.cmd(("normal %dGzD"):format(node.range[2] - 1))
  end)
  vim.fn.winrestview(saved)

  local height = math.max(
    node.params and node.params.height or (node.range[2] - node.range[1] + 1),
    config.minimum_inline_fence_height
  )
  -- Nothing to fold
  if height >= node.range[2] - node.range[1] + 1 then
    return
  end

  pcall(function()
    vim.cmd(("%d,%dfold"):format(
      node.range[1] + height - 1 - 1,
      node.range[2] - 1
    ))
  end)
end


---@type ExtmarkModuleAdd
function sixel_inline.add(node, path)
  refold(node)

  return sixel_extmarks.create(
    node.range[1] - 1,
    node.range[2] - 1,
    path.path
  )
end


---@type ExtmarkModuleRemove
function sixel_inline.remove(extmark_id)
  sixel_extmarks.remove(extmark_id)
end


---@type ExtmarkModuleIterIDs
function sixel_inline.iter_ids()
  local all_sixel = sixel_extmarks.get(0, -1)
  local i = 0
  return function()
    local current = all_sixel[i]
    while current ~= nil do
      i = i + 1
      current = all_sixel[i]
      if current.type == "inline" then return i, current end
    end
  end
end


---@type ExtmarkModuleRedraw
function sixel_inline.redraw(force)
  if force then
    sixel_extmarks.clear_screen(true)
  end
  sixel_extmarks.redraw(force)
  sixel_extmarks.redraw(force)
end


---@type ExtmarkModuleDump
function sixel_inline.dump(extmark_id_to_node)
  vim.print(
    vim.tbl_map(function(x) return {
      node_id = (extmark_id_to_node[x.id] or {}).id,
      height = x.height,
      start_row = x.start_row
    } end, sixel_extmarks.get(0, -1))
  )
end

return sixel_inline
