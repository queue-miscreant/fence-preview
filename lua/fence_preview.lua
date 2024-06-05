-- fence_preview.lua
--
-- Lua callbacks for the Python backend
-- Generally ensures that "fast" callbacks such as creating new extmarks
-- done without IPC overhead.

---@class node
---@field content string
---@field filetype string
---@field range [integer, integer]

---@diagnostic disable-next-line
fence_preview = {
  ---@type node[]
  node_cache = {},
  ---@type parsing_node[]
  last_nodes = {}
}


---@param buffer integer
---@param path string
---@param node parsing_node
function fence_preview.try_draw_extmark(buffer, path, node)
  -- TODO: the node received should be compared against nodes in the current buffer
  vim.api.nvim_buf_call(buffer, function()
    sixel_extmarks.create(node.start - 1, node.end_ - 1, path)
  end)
end


function fence_preview.bind()
  vim.cmd [[
    augroup ImageExtmarks
      autocmd! TextChanged,InsertLeave
    augroup END
  ]]

  vim.api.nvim_create_autocmd(
    { "TextChanged", "InsertLeave" },
    {
      buffer = 0,
      callback = function()
        ---@type integer
        local current_buffer = vim.api.nvim_get_current_buf()
        ---@type string[]
        local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, 0)

        local nodes = fence_preview.generate_nodes(current_lines)

        -- Cursor
        vim.b.fence_preview_inside_node = nil
        local cursor_line = vim.fn.line(".")
        for _, node in ipairs(nodes) do
          -- Cursor is inside this node
          if (node.start < cursor_line and cursor_line < node.end_) then
            vim.b.fence_preview_inside_node = node.id
            break
          end
        end

        -- Push external content to Python for running
        sixel_extmarks.remove_all()
        vim.fn.FenceAsyncGen(
          current_buffer,
          vim.tbl_filter(
            function(node) return node.id ~= vim.b.fence_preview_inside_node end,
            nodes
          )
        )

        fence_preview.last_nodes = nodes
      end
    }
  )

  -- Push content in fences if the cursor has moved out of the way
  vim.api.nvim_create_autocmd(
    { "CursorMoved" },
    {
      buffer = 0,
      callback = function()
        if vim.b.fence_preview_inside_node == nil then return end

        vim.fn.FenceAsyncGen(
          vim.api.nvim_get_current_buf(),
          vim.tbl_filter(
            function(node) return node.id == vim.b.fence_preview_inside_node end,
            fence_preview.last_nodes
          )
        )

        vim.b.fence_preview_inside_node = nil
      end
    }
  )

  vim.api.nvim_buf_create_user_command(
    0,
    "OpenFence",
    function() fence_preview.try_enter_window() end,
    {}
  )
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
    vim.split(node.content:sub(0, -2), "\n")
  )
  vim.api.nvim_set_option_value("filetype", node.filetype, { buf = new_buffer })
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
      vim.api.nvim_buf_set_lines(
        current_buffer,
        node.range[1],
        node.range[2] - 1,
        0,
        vim.api.nvim_buf_get_lines(new_buffer, 0, -1, 0)
      )

      -- TODO: scroll parent buffer and update extmarks

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

      for _, other_node in pairs(fence_preview.node_cache) do
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

---@class parsing_node
---@field type "fence"|"file"
---@field parameters string
---@field start integer
---@field end_? integer
---@field content? string[]
---@field id? integer

---@param node parsing_node
---@return parsing_node
local function cook_node(node)
  if node.type == "file" then
    node.start = node.start + 1
  end

  return node
end

---@param lines string[]
---@return parsing_node[]
function fence_preview.generate_nodes(lines)
  ---@type parsing_node[]
  local nodes = {}
  ---@type parsing_node|nil
  local current_node = nil
  local line_for_file = false

  for line_number, line in pairs(lines) do
    -- Cut off and push the image node if the line is not empty
    if line_for_file and line ~= "" then
      assert(current_node ~= nil)
      current_node.end_ = line_number - 1
      current_node.id = #nodes + 1
      table.insert(nodes, cook_node(current_node))

      current_node = nil
      line_for_file = false
    end

    -- Content like this: "```[params]". Used to delimit fences
    local fence_parameters = line:match("^%s*```([^`]*)")
    if fence_parameters ~= nil then
      -- Fence beginning
      if current_node == nil then
        current_node = {
          type = "fence",
          parameters = fence_parameters,
          start = line_number
        }
      -- Fence ending, push node
      else
        current_node.end_ = line_number
        current_node.id = #nodes + 1
        current_node.content= {}
        if current_node.start + 1 <= current_node.end_ then
          table.move(
            lines,
            current_node.start + 1,
            current_node.end_ - 1,
            1,
            current_node.content
          )
        end
        table.insert(nodes, cook_node(current_node))
        current_node = nil
      end
      goto next
    end

    -- Content [like this](params)
    -- `params` should contain filename
    local file_parameters = line:match("^!%[[^%]]*%]%(([^%)]*)%)$")
    if file_parameters ~= nil then
      current_node = {
        type = "file",
        parameters = file_parameters,
        start = line_number
      }
      line_for_file = true
    end

    ::next::
  end

  return nodes
end
