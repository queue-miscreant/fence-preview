-- extmarks/sixel_virtual.lua
--
-- Virtual sixel extmark provider.
-- Newer `sixel_extmarks` functionality for Neovim >= 0.10
-- Images render "inside" virtual lines added to the buffer

local loaded, sixel_extmarks = pcall(function() return require "sixel_extmarks" end)
if not loaded then
  vim.notify(
    "fence_preview: Missing dependency nvim_image_extmarks",
    vim.log.levels.ERROR
  )
  return {}
end
local config = require "fence_preview.config"

local sixel_virtual = {
  name = "sixel_virtual"
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

  -- TODO: modify vimwiki's suggested fold function to work with fences
  -- Fold the entire content so that we can rely on the virtual lines
  pcall(function()
    vim.cmd(("%d,%dfold"):format(
      node.range[1],
      node.range[2] - 1
    ))
  end)
end


---@type ExtmarkModuleAdd
function sixel_virtual.add(node, path)
  refold(node)

  -- Place the extmark right after the fence
  local start_line = node.range[2]
  local height = node.range[2] - node.range[1] + 1
  if node.type == "file" then
    -- Place the extmark right below the image
    start_line = node.range[1]
    height = config.default_virtual_file_height
  elseif --[[ node.type == "fence" and ]] node.params.height ~= nil then
    height = node.params.height
  end

  return sixel_extmarks.create_virtual(
    start_line - 1,
    height,
    path.path
  )
end


---@type ExtmarkModuleRemove
function sixel_virtual.remove(extmark_id)
  sixel_extmarks.remove(extmark_id)
end


---@type ExtmarkModuleIterIDs
function sixel_virtual.iter_ids()
  local all_sixel = sixel_extmarks.get(0, -1)
  local i = 0
  return function()
    local current = all_sixel[i]
    while current ~= nil do
      i = i + 1
      current = all_sixel[i]
      if current.type == "virtual" then return i, current end
    end
  end
end


---@type ExtmarkModuleRedraw
function sixel_virtual.redraw(force)
  sixel_extmarks.redraw(force)
end


---@type ExtmarkModuleDump
function sixel_virtual.dump(extmark_id_to_node)
  vim.print(
    vim.tbl_map(function(x) return {
      node_id = (extmark_id_to_node[x.id] or {}).id,
      height = x.height,
      start_row = x.start_row
    } end, sixel_extmarks.get(0, -1))
  )
end


return sixel_virtual --[[@as ExtmarkModule]]
