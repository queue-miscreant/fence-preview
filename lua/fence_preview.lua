fence_preview = {}

---@param updated_range_paths [integer, integer, string][]
function fence_preview.push_new_content(updated_range_paths)
  for i, range_path in ipairs(updated_range_paths) do
    sixel_extmarks.create(unpack(range_path))
  end
  -- No idea why this helps
  fence_preview.bind()
end

function fence_preview.bind()
  vim.cmd [[
    augroup VimImage
      autocmd! TextChanged
      autocmd TextChanged <buffer> call FenceUpdateContent()
      autocmd InsertLeave <buffer> call FenceUpdateContent()
    augroup END
  ]]
end
