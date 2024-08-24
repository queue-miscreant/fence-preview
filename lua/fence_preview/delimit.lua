-- delimit.lua
--
-- Functions for assembling a list of nodes (fences or files) for current buffer content.
-- This should probably get rewritten for treesitter, but patterns are fine for the moment

local delimit = {}

local node_metatable = {}

-- Allow extensions outside of this file
delimit.node_metatable = node_metatable


---@param params_list string[]
---@return FenceParams|nil
local function parse_node_parameters(params_list)
  local filetype = nil
  local height = nil

  ---@type string[]
  local others = {}

  local params = table.concat(params_list, ",")
  for i, param in ipairs(vim.split(params, ",")) do
    ---@type string
    local trimmed_param = vim.trim(param)

    if i == 1 then
      filetype = trimmed_param
    elseif trimmed_param:find("height") == 1 then
      ---@type string[]
      local equal = vim.split(trimmed_param, "=")

      if #equal > 1 then
        local temp_height = tonumber(equal[2])
        if temp_height ~= nil then
          height = temp_height
        end
      end
    else
      table.insert(others, trimmed_param)
    end
  end

  if filetype == nil then
    return nil
  end

  return {
    filetype = filetype,
    height = height,
    others = others
  }
end

---@class ParsingNode
---@field type "fence"|"file"
---@field parameters string[]
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
    local filename = node.parameters[1]
    ---@type FileNode
    ret = {
      type = "file",
      filename = filename,
      range = {node.start + 1, node.end_},
      id = node.id,
      hash = vim.fn.sha256(filename),
      buffer = buffer_number,
      logs = {},
    }
  else
    local parsed = parse_node_parameters(node.parameters)
    if parsed == nil then return nil end
    if #node.content == 0 then return nil end

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
    local fence_parameters = line:match("^%s*```([^`]*)")
    if fence_parameters ~= nil then
      -- Fence beginning
      if current_node == nil then
        current_node = {
          type = "fence",
          parameters = { fence_parameters },
          start = line_number
        }
      -- Fence ending, push node
      else
        table.insert(current_node.parameters, fence_parameters)
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

    -- Content [like this](params)
    -- `params` should contain filename
    local file_parameters = line:match("^!%[[^%]]*%]%(([^%)]*)%)$")
    if file_parameters ~= nil then
      current_node = {
        type = "file",
        parameters = { file_parameters },
        start = line_number
      }
      line_for_file = true
    end

    ::next::
  end

  return nodes
end

return delimit
