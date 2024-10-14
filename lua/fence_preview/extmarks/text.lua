-- extmarks/text.lua
--
-- Text extmark provider.
-- Includes converters for general Lua objects, trimming extra lines according
-- to user preference.
-- This functionality is also used for displaying errors.

local config = require "fence_preview.config"

local TEXT_NAMESPACE = vim.api.nvim_create_namespace("fence-preview-text")

local text = {
  name = "text"
}

-- Remove empty lines before and after a list of nonempty lines, then return a
-- list with at most target_length lines, trimming with an ellipsis if necessary.
--
---@param message string[]
---@param target_length integer
local function trim_to_line_count(message, target_length)
  local start = #message
  local end_ = 1
  for i = 1, #message do
    if message[i] ~= "" then
      start = i
      break
    end
  end

  for i = #message, 1, -1 do
    if message[i] ~= "" then
      end_ = i
      break
    end
  end

  if end_ - start + 1 > target_length then
    local ret = vim.list_slice(message, start, start + target_length - 1)
    table.insert(ret, "...")
    return ret
  end

  return vim.list_slice(message, start, end_)
end


-- Convert a generic table (or string or integer) to something that can be used as
-- an argument to `nvim_buf_set_extmark`.
--
---@param range [integer, integer] The range of the node this message belongs to
---@param message any The message to render as an extmark
---@param highlight string The highlight to use within the extmark
---@return VirtTextArgs|VirtLinesArgs, integer
local function message_to_extmark(range, message, highlight)
  ---@type VirtTextArgs|VirtLinesArgs
  local extmark_args
  local start_line = range[1]
  if type(message) == "table" then
    if type(message[1]) == "string" then
      if #message == 1 then
        extmark_args = {
          virt_text = {{ tostring(message), highlight }},
          virt_text_pos = "eol",
        }
      else
        start_line = range[2]
        extmark_args = {
          virt_lines = vim.tbl_map(
            function(line)
              ---@type HLPair[]
              return {{ tostring(line), highlight }}
            end,
            trim_to_line_count(message, config.maximum_text_lines)
          )
        } --[[@as VirtLinesArgs]]
      end
    else
      start_line = range[2]
      extmark_args = {
        virt_lines = vim.tbl_map(
          function(line)
            ---@type HLPair[]
            return {{ tostring(line), highlight }}
          end,
          trim_to_line_count(
            vim.split("\n", vim.inspect(message)),
            config.maximum_text_lines
          )
        )
      } --[[@as VirtLinesArgs]]
    end
  else
    extmark_args = {
      virt_text = {{ tostring(message), highlight }},
      virt_text_pos = "eol",
    }
  end

  return extmark_args, start_line
end


---@param node Node
---@param message any
---@param highlight string
function text.add_text(node, message, highlight)
  local extmark_args, start_line = message_to_extmark(node.range, message, highlight)
  return vim.api.nvim_buf_set_extmark(
    0,
    TEXT_NAMESPACE,
    start_line - 1,
    0,
    extmark_args
  )
end


---@type ExtmarkModuleAdd
function text.add(node, path)
  return text.add_text(
    node,
    path.path,
    "FencePreviewPath"
  )
end


---@type ExtmarkModuleRemove
function text.remove(extmark_id)
  vim.api.nvim_buf_del_extmark(0, TEXT_NAMESPACE, extmark_id)
end


---@type ExtmarkModuleIterIDs
function text.iter_ids()
  return ipairs(
    vim.tbl_map(
      function(x) return x[1] end,
      vim.api.nvim_buf_get_extmarks(0, TEXT_NAMESPACE, 0, -1, {})
    )
  )
end


return text
