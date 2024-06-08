-- delimit.lua
--
-- Functions for assembling a list of nodes (fences or files) for current buffer content.
-- This should probably get rewritten for treesitter, but patterns are fine for the moment

local delimit = {}

---@class parsing_node
---@field type "fence"|"file"
---@field parameters string[]
---@field start integer
---@field end_? integer
---@field content? string[]
---@field id? integer
---@field hash? string

---@class fence_params
---@field filetype string
---@field height? integer
---@field content string[]
---@field others string[]

---@class fence_node
---@field type "fence"
---@field content string[]
---@field params fence_params
---@field range [integer, integer]
---@field id integer
---@field hash string
---@field extmark_id? integer

---@class file_node
---@field type "file"
---@field filename string
---@field range [integer, integer]
---@field id integer
---@field hash string
---@field extmark_id? integer

---@alias node fence_node|file_node


---@param params_list string[]
---@return fence_params|nil
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


---@param node parsing_node
---@return node|nil
local function cook_node(node)
  if node.type == "file" then
    local filename = node.parameters[1]
    ---@type file_node
    return {
      type = "file",
      filename = filename,
      range = {node.start + 1, node.end_},
      id = node.id,
      hash = vim.fn.sha256(filename)
    }
  else
    local parsed = parse_node_parameters(node.parameters)
    if parsed == nil then return nil end
    if #node.content == 0 then return nil end

    ---@type fence_node
    return {
      type = "fence",
      params = parsed,
      content = node.content,
      range = {node.start, node.end_},
      id = node.id,
      hash = vim.fn.sha256(vim.trim(table.concat(node.content, "\n")))
    }
  end
end


---@param node node
---@param content string[]
function delimit.set_node_content(node, content)
  node.content = content
  node.hash = vim.fn.sha256(vim.trim(table.concat(content, "\n")))
end


---@param lines string[]
---@return node[]
function delimit.generate_nodes(lines)
  ---@type node[]
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

      local cooked = cook_node(current_node)
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

        local cooked = cook_node(current_node)
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
