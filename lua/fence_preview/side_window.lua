-- side_window.lua
--
-- Functions for opening up a split for editing fence content, while previewing
-- the result in the main buffer.

local delimit = require "fence_preview.delimit"
local generate_content = require "fence_preview.generate_content"

local side_window = {}


---@param node fence_node
function side_window.enter_window(node)
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_window = vim.api.nvim_get_current_win()

  local current_cursor = vim.api.nvim_win_get_cursor(0)
  -- Move cursor outside the range
  -- TODO: if the fence is the only content in the buffer, then this doesn't make sense!
  vim.api.nvim_win_set_cursor(0, { node.range[1] - 1, 0 })

  local new_buffer = vim.api.nvim_create_buf(0, 0)
  -- TODO: preamble for TeX (and potentially other content)
  vim.api.nvim_buf_set_lines(
    new_buffer,
    0,
    -1,
    0,
    node.content
  )
  vim.api.nvim_set_option_value("filetype", node.params.filetype, { buf = new_buffer })
  vim.api.nvim_set_option_value("buftype", nil, { buf = new_buffer })
  -- Set a temporary filename for linting plugins that depend on that
  vim.api.nvim_buf_set_name(new_buffer, vim.fn.tempname())

  local new_window = vim.api.nvim_open_win(
    new_buffer,
    true,
    {
      win = 0,
      split = "right"
    }
  )
  vim.api.nvim_win_set_cursor(new_window, {current_cursor[1] - node.range[1], 0})

  vim.api.nvim_create_autocmd({"BufWrite"}, {
    buffer = new_buffer,
    callback = function()
      delimit.set_node_content(node, vim.api.nvim_buf_get_lines(new_buffer, 0, -1, 0))
      vim.api.nvim_buf_set_lines(
        current_buffer,
        node.range[1],
        node.range[2] - 1,
        0,
        node.content
      )

      vim.b.draw_number = (vim.b.draw_number or 0) + 1
      generate_content.pipe_nodes(
        { node },
        vim.b.draw_number
      )

      -- Write parent buffer
      vim.api.nvim_buf_call(current_buffer, function()
        if (
          vim.api.nvim_buf_get_name(0) == "" or
          vim.api.nvim_get_option_value("readonly", {buf = 0})
        ) then return end
        vim.cmd("w")
      end)

      local num_lines = vim.fn.line("$")
      -- Early return if no change to number of lines
      if num_lines == node.range[2] - node.range[1] - 1  then return end

      -- Update the window and buffer
      local offset = node.range[1] + num_lines + 1 - node.range[2]
      node.range[2] = node.range[2] + offset

      for _, other_node in pairs(fence_preview.last_nodes) do
        if other_node.range[1] > node.range[2] then
          other_node.range[1] = other_node.range[1] + offset
          other_node.range[2] = other_node.range[2] + offset
        end
      end
    end
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = new_buffer,
    callback = function()
      vim.api.nvim_win_call(new_window, function()
        vim.api.nvim_buf_delete(0, { force = true })
      end)
    end
  })
end

return side_window
