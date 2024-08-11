local path = require "fence_preview.polyfill.path"
local subprocess = require "fence_preview.polyfill.subprocess"

local gnuplot = {}

-- Read a file and pass its contents as a list of strings
--
---@type pipeline_stage
function gnuplot.read_file(args, callback, error_callback)
  local file_path = args.previous --[[@as path]]

  local file = io.open(file_path.path)
  if file == nil then
    error_callback(("Could not read file `%s`"):format(file_path))
    return
  end

  local content = file:read("a")
  file:close()

  return vim.split(content, "\n")
end

-- Pipe the argument (as a list of strings) through gnuplot, targeting a PNG file.
-- Passes the resulting filepath if successful.
--
---@type pipeline_stage
function gnuplot.gnuplot_to_png(args, callback, error_callback)
  local content = args.previous --[[@as string[] ]]
  local png_path = path.new_temp(args.node.hash, ".png")

  local preamble = ("set output '%s'\nset terminal png\n"):format(png_path)

  local _, stdin = subprocess.spawn("gnuplot",
    {
      args ={ "-" },
      stdio = { true, false, true },
      cwd = path.tempdir,
    },
    function(ret)
      if ret.code ~= 0 then
        -- TODO: gnuplot error handling
        args.node:log(ret.stdout)
        args.node:log(ret.stderr)
        args.node:log(args)
        error_callback("gnuplot error:\n" .. vim.split(ret.stderr, "\n"))
        return
      end

      callback(png_path)
    end,
    function()
      error_callback("gnuplot timed out!")
    end
  )
  if stdin == nil then return end

  stdin:write(
    preamble .. table.concat(content, "\n"),
    function() stdin:shutdown() end
  )
end

return gnuplot
