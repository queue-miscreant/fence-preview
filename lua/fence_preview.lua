fence_preview = {}

---@param updated_range_paths [integer, integer, string][]
function fence_preview.push_new_content(updated_range_paths)
  for i, range_path in ipairs(updated_range_paths) do
    create_image_extmark(unpack(range_path))
  end
  -- No idea why this helps
  fence_preview.bind()
end

function fence_preview.bind()
  vim.cmd [[
    augroup VimImage
      autocmd! TextChanged,TextChangedI
      autocmd TextChanged,TextChangedI <buffer> call FenceUpdateContent()
    augroup END
  ]]
end
