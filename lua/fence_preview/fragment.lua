local Path = require("fence_preview.polyfill.path")
local update = require("fence_preview.update")

local fragment = {}

---@param fragment_dir Path
local function newest_fragment(fragment_dir, extension)
  return Path.new(
    tostring(#vim.fn.readdir(fragment_dir.path) + 1)
  )
  ---@diagnostic disable-next-line
    :relative_to(fragment_dir)
    :with_suffix(extension)
end

---@param filetype string
local function filetype_to_extension(filetype)
  if filetype == "math" or filetype == "latex" then
    return ".tex"
  end
end

---@param base_path Path
---@param filetype string
---@return Path | nil
local function new_fragment(base_path, filetype)
  local parent_dir = base_path:parent()
  local extension = filetype_to_extension(filetype)
  if not extension then return end
  ---@diagnostic disable-next-line
  local fragment_dir = Path.new("fragments"):relative_to(parent_dir)

  local fragment_file
  if fragment_dir:exists_dir() then
    fragment_file = newest_fragment(fragment_dir, extension)
  else
    local named_fragment_dir = base_path:with_suffix("")
    if not named_fragment_dir:exists_dir() then
      vim.fn.mkdir(named_fragment_dir.path)
    end
    fragment_file = newest_fragment(named_fragment_dir, extension)
  end

  return fragment_file
end

---@param node FenceNode
function fragment.from_fence(node)
  vim.api.nvim_buf_call(node.buffer, function()
    local filetype = node.params.filetype
    local fragment_file = new_fragment(
      Path.new(vim.fn.bufname()),
      filetype
    )

    if not fragment_file then
      vim.notify(
        ("Cannot convert filetype '%s' to extension"):format(filetype),
        vim.log.levels.WARN
      )
      return
    end

    vim.fn.writefile(node.content, fragment_file.path)

    vim.api.nvim_buf_set_lines(
      0,
      node.range[1] - 1,
      node.range[2],
      0,
      { ("![](%s)"):format(fragment_file.path) }
    )

    update.current_buffer()
  end)
end

return fragment
