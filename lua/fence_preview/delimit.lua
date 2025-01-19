-- delimit.lua
--
-- Functions for assembling a list of nodes (fences or files) for current buffer content.
-- This should probably get rewritten for treesitter, but patterns are fine for the moment

local delimit = {}

local node_metatable = {}

-- Allow extensions outside of this file
delimit.node_metatable = node_metatable


-- Parse extra parameters from the first line of content
--
---@param extra_params string
---@return FenceParams
local function parse_node_parameters(extra_params)
  ---@type FenceParams
  local params = {} ---@diagnostic disable-line

  -- Fetch content parameters from `extra_params`
  -- These are typically supplied on the first line of the content
  local content_params = extra_params:match("^%W*([%w =,]+)$") or ""
  for _, param in ipairs(vim.split(content_params, ",")) do
    ---@type string
    local trimmed = vim.trim(param)

    ---@type string[]
    local equal = vim.split(trimmed, "=")
    if #equal > 1 then
      params[trimmed] = tonumber(equal[2]) or equal[2]
    elseif vim.tbl_contains({"math", "latex", "image"}, trimmed) then
      params.as = param
    else
      params[trimmed] = true
    end
  end

  return params
end

---@class ParsingNode
---@field type "fence"|"file"
---@field parameter string
---@field start integer
---@field end_? integer
---@field content? string[]
---@field id? integer
---@field hash? string

---@param node ParsingNode
---@return Node|nil
local function cook_node(node, buffer_number)
  ---@type Node
  local ret

  if node.type == "file" then
    local filename = node.parameter
    ---@type FileNode
    ret = {
      type = "file",
      filename = filename,
      range = {node.start, node.end_},
      id = node.id,
      hash = vim.fn.sha256(filename),
      buffer = buffer_number,
      logs = {},
    }
  else
    if #node.content == 0 then return nil end

    local parsed = parse_node_parameters(node.content[1])
    parsed.filetype = vim.trim(node.parameter)

    ---@type FenceNode
    ret = {
      type = "fence",
      params = parsed,
      content = node.content,
      range = {node.start, node.end_},
      id = node.id,
      hash = vim.fn.sha256(vim.trim(table.concat(node.content, "\n"))),
      buffer = buffer_number,
      logs = {},
    }
  end

  setmetatable(ret, node_metatable)
  node_metatable.__index = node_metatable
  return ret
end


---@param node Node
---@param content string[]
function delimit.set_node_content(node, content)
  node.content = content
  node.hash = vim.fn.sha256(vim.trim(table.concat(content, "\n")))
end


---@param self Node
---@param line integer
---@return boolean
function node_metatable:is_line_inside(line)
  -- Cursor is inside this node
  return self.range[1] <= line and line < self.range[2]
end

---@param self Node
---@param other Node
---@return boolean
function node_metatable:equals(other)
  -- Nodes have the same content
  return self.hash == other.hash
end

---@param self Node
---@param ... any
function node_metatable:log(...)
  local args = { ... }
  for _, entry in ipairs(args) do
    if type(entry) ~= "string" then
      entry = vim.inspect(entry)
    end
    vim.list_extend(self.logs, vim.split(entry, "\n"))
  end
end

---@param self Node
function node_metatable:log_self()
  self:log({
    type = self.type,
    content = self.content,
    params = self.params,
    range = self.range,
    id = self.id,
    hash = self.hash,
    buffer = self.buffer,
  })
end

---@param self Node
function node_metatable:clear_logs()
  self.logs = {}
end


-- Build up a list of nodes from the data in `lines`.
-- Nodes are either markdown links on their own line beginning with a !,
-- or a region of text enclosed in triple-backticks with a filetype.
--
---@param lines string[]
---@param buffer_number integer
---@return Node[]
function delimit.generate_nodes(lines, buffer_number)
  ---@type Node[]
  local nodes = {}
  ---@type ParsingNode|nil
  local current_node = nil
  local line_for_file = false

  for line_number, line in pairs(lines) do
    -- Cut off and push the image node if the line is not empty
    if line_for_file and line ~= "" then
      assert(current_node ~= nil)
      current_node.end_ = line_number - 1
      current_node.id = #nodes + 1

      local cooked = cook_node(current_node, buffer_number)
      if cooked ~= nil then
        table.insert(nodes, cooked)
      end

      current_node = nil
      line_for_file = false
    end

    -- Content like this: "```[params]". Used to delimit fences
    local filetype = line:match("^%s*```([^`]*)")
    if filetype ~= nil then
      -- Fence beginning
      if current_node == nil then
        current_node = {
          type = "fence",
          parameter = filetype,
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

        local cooked = cook_node(current_node, buffer_number)
        if cooked ~= nil then
          table.insert(nodes, cooked)
        end

        current_node = nil
      end
      goto next
    end

    -- Content ![like this](params)
    -- `params` should contain filename
    local file_parameter = line:match("^!%[[^%]]*%]%(([^%)]*)%)$")
    if file_parameter ~= nil then
      current_node = {
        type = "file",
        parameter = file_parameter,
        start = line_number
      }
      line_for_file = true
    end

    ::next::
  end

  -- Cut off and push the image node if the line is not empty
  if line_for_file then
    assert(current_node ~= nil)
    current_node.end_ = #lines - 1
    current_node.id = #nodes + 1

    local cooked = cook_node(current_node, buffer_number)
    if cooked ~= nil then
      table.insert(nodes, cooked)
    end

    current_node = nil
    line_for_file = false
  end

  return nodes
end

return delimit
