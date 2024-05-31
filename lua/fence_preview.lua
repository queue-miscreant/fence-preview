-- fence_preview.lua
--
-- Lua callbacks for the Python backend
-- Generally ensures that "fast" callbacks such as creating new extmarks
-- done without IPC overhead.

fence_preview = {}

---@param updated_range_paths [integer, integer, string][]
function fence_preview.push_new_content(updated_range_paths)
  sixel_extmarks.disable_drawing()
  sixel_extmarks.remove_all()
  for i, range_path in ipairs(updated_range_paths) do
    sixel_extmarks.create(unpack(range_path)) ---@diagnostic disable-line
  end
  sixel_extmarks.enable_drawing()
  -- No idea why this helps
  -- fence_preview.bind()
end

function fence_preview.bind()
  vim.cmd [[
    augroup ImageExtmarks
      autocmd! TextChanged,InsertLeave
      autocmd TextChanged <buffer> call FenceUpdateContent()
      autocmd InsertLeave <buffer> call FenceUpdateContent()
    augroup END
  ]]
end
