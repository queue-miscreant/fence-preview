local path = require "fence_preview.polyfill.path"
local subprocess = require "fence_preview.polyfill.subprocess"

local python = {}

-- Pipe the argument (as a list of strings) into a Python interpreter,
-- Passes along the output lines if successful.
--
---@type PipelineStage
function python.run_python(args, callback, error_callback)
  local code = args.previous --[[@as string[] ]]

  local _, stdin = subprocess.spawn("python",
    {
      args ={ "-" },
      stdio = { true, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      args.node:log("Got stdout:")
      args.node:log(ret.stdout)

      if ret.code ~= 0 then
        args.node:log(ret.stderr)
        args.node:log(args)
        error_callback("Python error occurred")
        return
      end

      local params = args.node.params
      local next_stage = nil
      if vim.list_contains(params.others, "math") then
        -- Chain into math pipeline
        params["math"] = nil
        next_stage = "#math"
        args.node:log("Interpreting the above as a math block")
      elseif vim.list_contains(params.others, "latex") then
        -- Chain into LaTeX pipeline
        params["latex"] = nil
        next_stage = "#latex"
        args.node:log("Interpreting the above as a LaTeX block")
      elseif vim.list_contains(params.others, "image") then
        -- Display image
        next_stage = "display"
      else
        -- Show text
        next_stage = "text"
      end

      callback(vim.split(ret.stdout, "\n"), next_stage)
    end,
    function()
      error_callback("Python timed out!")
    end
  )
  if stdin == nil then return end

  stdin:write(
    table.concat(code, "\n"),
    function() stdin:shutdown() end
  )
end

return python
