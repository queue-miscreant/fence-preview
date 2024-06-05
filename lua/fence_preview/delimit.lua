-- delimit.lua
--
-- Functions for assembling a list of nodes (fences or files) for current buffer content.

local delimit = {}

---@class parsing_node
---@field type "fence"|"file"
---@field parameters string
---@field start integer
---@field end_? integer
---@field content? string[]
---@field id? integer

---@alias node parsing_node

---@param node parsing_node
---@return node
local function cook_node(node)
  if node.type == "file" then
    node.start = node.start + 1
  end

  return node
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

return delimit
