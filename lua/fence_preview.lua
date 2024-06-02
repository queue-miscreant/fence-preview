-- fence_preview.lua
--
-- Lua callbacks for the Python backend
-- Generally ensures that "fast" callbacks such as creating new extmarks
-- done without IPC overhead.

---@class node
---@field content string
---@field content_id string
---@field filetype string
---@field range [integer, integer]

---@diagnostic disable-next-line
fence_preview = {
  ---@type node[]
  node_cache = {}
}

---@param updated_range_paths [integer, integer, string][]
function fence_preview.push_new_content(updated_range_paths)
  sixel_extmarks.disable_drawing()
  sixel_extmarks.remove_all()
  for i, range_path in ipairs(updated_range_paths) do
    sixel_extmarks.create(unpack(range_path)) ---@diagnostic disable-line
  end
  sixel_extmarks.enable_drawing()
end

function fence_preview.set_nodes(buffer, nodes)
  fence_preview.node_cache = nodes
end

function fence_preview.bind()
  vim.cmd [[
    augroup ImageExtmarks
      autocmd! TextChanged,InsertLeave
    augroup END
  ]]

  vim.cmd [[
    augroup FencePreview
      autocmd!
      autocmd TextChanged <buffer> call FenceUpdateContent()
      autocmd InsertLeave <buffer> call FenceUpdateContent()
      autocmd CursorMoved <buffer> lua fence_preview.try_enter_window()
    augroup END
  ]]
end

---@return node|nil
local function cursor_in_node()
  if vim.fn.mode():sub(1, 1) ~= "n" then return end
  local cursor_line = vim.fn.line(".")
  local inside = vim.tbl_filter(
    ---@param node node
    function(node)
      return (
        node.filetype ~= vim.NIL and
        node.range[1] < cursor_line and
        cursor_line < node.range[2]
      )
    end,
  fence_preview.node_cache)

  if #inside == 0 then return nil end
  return inside[1]
end

function fence_preview.try_enter_window()
  local node = cursor_in_node()
  if node == nil then return end

  local current_cursor = vim.api.nvim_win_get_cursor(0)

  -- Move cursor outside the range
  vim.api.nvim_win_set_cursor(0, { node.range[1], 0 })
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_window = vim.api.nvim_get_current_win()

  local new_buffer = vim.api.nvim_create_buf(0, 0)
  vim.api.nvim_buf_set_lines(
    new_buffer,
    0,
    -1,
    0,
    vim.split(node.content:sub(0, -2), "\n")
  )
  vim.api.nvim_set_option_value("filetype", node.filetype, { buf = new_buffer })
  vim.api.nvim_set_option_value("buftype", nil, { buf = new_buffer })
  -- Set a temporary filename for linting plugins that depend on that
  vim.api.nvim_buf_set_name(new_buffer, vim.fn.tempname())

  vim.api.nvim_buf_set_keymap(new_buffer, "n", "k", "", {
    callback = function()
      if vim.fn.line(".") == 1 then
        vim.api.nvim_set_current_win(current_window)
      else
        vim.cmd "normal! k"
      end
    end
  })
  vim.api.nvim_buf_set_keymap(new_buffer, "n", "j", "", {
    callback = function()
      if vim.fn.line(".") == vim.fn.line("$") then
        vim.api.nvim_win_set_cursor(current_window, { node.range[2], 0 })
        vim.api.nvim_set_current_win(current_window)
      else
        vim.cmd "normal! j"
      end
    end
  })
  vim.api.nvim_buf_set_keymap(new_buffer, "n", "[[", "", {
    callback = function()
      if vim.fn.line(".") == 1 then
        vim.api.nvim_set_current_win(current_window)
      else
        vim.cmd "normal! [["
      end
    end
  })
  vim.api.nvim_buf_set_keymap(new_buffer, "n", "]]", "", {
    callback = function()
      if vim.fn.line(".") == vim.fn.line("$") then
        vim.api.nvim_win_set_cursor(current_window, { node.range[2], 0 })
        vim.api.nvim_set_current_win(current_window)
      else
        vim.cmd "normal! ]]"
      end
    end
  })

  local new_window = vim.api.nvim_open_win(
    new_buffer,
    1,
    {
      relative = "win",
      bufpos = { node.range[1] - 1, 0 },
      height = node.range[2] - node.range[1] - 1,
      width = vim.api.nvim_win_get_width(0),
      zindex = 10
    }
  )
  vim.api.nvim_win_set_cursor(new_window, {current_cursor[1] - node.range[1], 0})

  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    buffer = new_buffer,
    callback = function()
      vim.api.nvim_buf_set_lines(
        current_buffer,
        node.range[1],
        node.range[2] - 1,
        0,
        vim.api.nvim_buf_get_lines(new_buffer, 0, -1, 0)
      )

      local num_lines = vim.fn.line("$")
      -- Early return if no change to number of lines
      if num_lines == node.range[2] - node.range[1] - 1  then return end

      -- Update the window and buffer
      local offset = node.range[1] + num_lines + 1 - node.range[2]
      node.range[2] = node.range[2] + offset

      for i, other_node in pairs(fence_preview.node_cache) do
        if other_node.range[1] > node.range[2] then
          other_node.range[1] = other_node.range[1] + offset
          other_node.range[2] = other_node.range[2] + offset
        end
      end

      vim.api.nvim_win_set_config(
        new_window,
        {
          relative = "win",
          win = current_window,
          bufpos = { node.range[1] - 1, 0 },
          height = node.range[2] - node.range[1] - 1,
        }
      )
      sixel_extmarks.redraw()
    end
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = new_buffer,
    callback = function()
      vim.api.nvim_buf_call(
        current_buffer,
        function()
          local sixel = sixel_extmarks.get(node.range[1] - 1, node.range[1] + 1)[1]
          vim.print{sixel, node.range}
          if sixel ~= nil then
            sixel_extmarks.move(sixel.id, node.range[1] - 1, node.range[2] - 1)
          end
        end
      )

      vim.api.nvim_win_call(new_window, function()
        vim.api.nvim_buf_delete(0, { force = true })
      end)
    end
  })

  -- TODO: winleave doesn't know if the fence has gotten longer!
  -- Use more buffer-local variables to make sure that these changes are
  vim.api.nvim_create_autocmd("BufWrite", {
    buffer = new_buffer,
    callback = function()
      vim.api.nvim_buf_call(current_buffer, function()
        if (
          vim.api.nvim_buf_get_name(0) == "" or
          vim.api.nvim_get_option_value("readonly", {buf = 0})
        ) then return end
        vim.cmd("w")
      end)
    end
  })
end
