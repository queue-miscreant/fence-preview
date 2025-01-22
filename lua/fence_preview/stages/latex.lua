local config = require "fence_preview.config"
local subprocess = require "fence_preview.polyfill.subprocess"
local path = require "fence_preview.polyfill.path"

local latex = {}

local DARK_COLORS = [[
\pagecolor{black}
\color{white}
]]

local function is_document(lines)
  for _, line in ipairs(lines) do
    if line:find("\\begin{document}") then
      return true
    end
  end

  return false
end

-- Add a standard LaTeX preamble to lines which should always be interpreted in math mode.
--
---@type PipelineStage
function latex.add_math_preamble(args)
  local extra_packages = table.concat(
    vim.tbl_map(
      function(package) return ("\\usepackage{%s}"):format(package) end,
      config.latex.extra_packages
    ),
    "\n"
  )
  local extra_preamble = extra_packages .. "\n" .. config.latex.extra_preamble

  -- Background color based on current `background` option
  local background = config.latex.force_mode
  local extra_document = config.latex.extra_document
  if background == "dark" then
    extra_document = extra_document .. DARK_COLORS
  end

  local ret = {
    config.latex.math_start:format(extra_preamble, extra_document),
    unpack(args.previous), ---@diagnostic disable-line
  }
  table.insert(ret, config.latex.math_end)
  return ret
end


-- Writes the argument (as a list of strings) to a ".tex" file.
-- Passes the resulting filepath if successful.
--
---@type PipelineStage
function latex.write_tex(args, callback, error_callback)
  -- create a new tex file containing the equation
  local tex_path = path.new_temp(args.node.hash, ".tex")

  -- No need to write the file again, continue with pipeline
  if tex_path:exists() then return tex_path end

  -- Bad argument
  if
    type(args.previous) ~= "table"
    or type(args.previous[1]) ~= "string"
  then
    error_callback("Cannot write math file: invalid argument")
    return
  end

  local file = io.open(tex_path.path, "w")
  if file == nil then
    error_callback(("Could not open file `%s`"):format(tex_path))
    return
  end
  file:write(unpack(args.previous)) ---@diagnostic disable-line
  file:close()

  callback(tex_path)
end


-- Parse output from LaTeX process stdout into a more digestable form
-- TODO: Look at latex output more clearly
--
---@param buf string
---@return [string, string, any]
local function parse_latex_output(buf)
  local err = { "", "", nil }

  for _, elm in ipairs(vim.split(buf, "\n")) do
    ---@cast elm string
    if elm:find("! ", 1, true) ~= nil then
      err[1] = elm
    elseif elm:find("l.", 1, true) ~= nil and elm:find("Emergency stop", 1, true) == nil then
      -- TODO
      local _, elms = elm:match("^(1%.)?(.+)")
      if elm == elms then
        goto continue
      end

      local elm_one, _, rest = elms.partition(" ")
      local elm_two, _, _ = rest.partition(" ")

      err[3] = elm_one

      if elm_two ~= "" then
        err[1] = elm_two
      end
    end
    ::continue::
  end

  return err
end


function latex.check_document(args, callback, error_callback)
  local tex_path = args.previous --[[@as Path]]
  if tex_path.exists == nil or not tex_path:exists() then
    error_callback("LaTeX file not found")
    return
  end

  local file_contents = vim.fn.readfile(tex_path.path)
  if not is_document(file_contents) then
    local with_preamble = latex.add_math_preamble({
      previous = file_contents,
      node = args.node,
    })
    latex.write_tex({
      previous = with_preamble,
      node = args.node,
    }, callback, error_callback)
    return
  end

  return args.previous
end


-- Run `latex` on the argument, which should be the path a TeX file.
-- Passes the resulting filepath if successful.
--
---@type PipelineStage
function latex.generate_dvi_from_latex(args, callback, error_callback)
  local tex_path = args.previous --[[@as Path]]
  if tex_path.exists == nil or not tex_path:exists() then
    error_callback("LaTeX file not found")
    return
  end

  -- use latex to generate a dvi
  local dvi_path = tex_path:with_suffix(".dvi")
  -- Skip if the dvi already exists
  if dvi_path:exists() then return dvi_path end

  subprocess.spawn("latex",
    {
      args = { tex_path.path },
      stdio = { false, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      args.node:log(ret.stdout)
      args.node:log(ret.stderr)
      if
        -- TODO: latex error codes are not reliable for detecting fatal errors
        ret.code ~= 0
      then
        -- LaTeX prints error to the stdout, if this is empty, then something is fundamentally
        -- wrong with the latex binary (for example shared library error). In this case just
        -- exit the program
        if ret.stdout == "" then
          error_callback("Detected fatal LaTeX error! Check your installation.")
          return
        end

        -- TODO: LaTeX error hints
        error_callback(
          "LaTeX failed to compile!"
          -- parse_latex_output(ret.stderr)[1]
        )
        return
      end

      callback(dvi_path)
    end,
    function()
      error_callback("LaTeX timed out!")
    end
  )
  -- Extra args from Rust:
  --
  -- .arg("--jobname").arg(&dvi_path)
  -- .expect("Could not spawn latex");
end


-- Convert the argument, which should be the path to an DVI file, to a SVG.
-- Passes the resulting filepath if successful.
--
---@type PipelineStage
function latex.generate_svg_from_dvi(args, callback, error_callback)
  local dvi_path = args.previous --[[@as Path]]
  if dvi_path.exists == nil or not dvi_path:exists() then error_callback("DVI file not found") return end

  -- convert the dvi to a svg file with the woff font format
  local svg_path = dvi_path:with_suffix(".svg")

  -- Skip if the SVG already exists
  if svg_path:exists() then return svg_path end

  subprocess.spawn("dvisvgm",
    {
      args ={ "--no-fonts", "--zoom=2.5", dvi_path.path },
      stdio = { false, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      args.node:log(ret.stdout)
      if ret.code ~= 0 or ret.stderr:find("error:", 1, true) ~= nil then
        args.node:log(ret.stderr)
        error_callback("Could not render DVI to SVG!")
        return
      end

      callback(svg_path)
    end,
    function()
      error_callback("dvisvgm timed out!")
    end
  )
end


-- Convert the argument, which should be the path to a vector file, to a raster
-- image (specifically PNG) using ImageMagick.
-- Passes the resulting filepath if successful.
--
---@type PipelineStage
function latex.rasterize(args, callback, error_callback)
  local svg_path = args.previous --[[@as Path]]
  if not svg_path.exists or not svg_path:exists() then error_callback("SVG file not found") return end

  -- convert the dvi to a svg file with the woff font format
  local png_path = svg_path:with_suffix(".png")

  -- Skip if the PNG already exists
  if png_path:exists() then return png_path end

  subprocess.spawn("magick",
    {
      args ={ "-density", "600", svg_path.path, png_path.path },
      stdio = { false, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      args.node:log(ret.stdout)
      if ret.code ~= 0 then
        args.node:log(ret.stderr)
        error_callback("An unknown error occurred in ImageMagick")
        return
      end

      callback(png_path)
    end,
    function()
      error_callback("ImageMagick timed out!")
    end
  )
end

return latex
