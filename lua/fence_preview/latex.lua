local pipeline = require "fence_preview.pipeline"
local path = require "fence_preview.path"

MATH_START = [[
\documentclass[20pt, preview]{standalone}
\nonstopmode
\usepackage{amsmath,amsfonts,amsthm}
\usepackage{xcolor}
\begin{document}
\[
]]

MATH_END = [[
\]
\end{document}
]]

local latex = {
}


-- local latex_path = shutil.which("latex")
-- if latex_path == nil then
--   error("Could not find LaTeX installation!")
-- end

-- local dvisvgm_path = shutil.which("dvisvgm")
-- if dvisvgm_path == nil then
--   error("Could not find dvisvgm!")
-- end


---@type pipeline_stage
function latex.add_math_preamble(args, callback, _)
  local ret = { MATH_START, unpack(args.previous) } ---@diagnostic disable-line
  table.insert(ret, MATH_END)
  callback(ret)
end


-- Writes the argument (as a list of strings) to a ".tex" file.
-- Passes along the resulting filepath if successful.
--
---@type pipeline_stage
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


-- Run `latex` on the argument, which should be the path a TeX file.
-- Passes the resulting DVI file if successful.
--
---@type pipeline_stage
function latex.generate_dvi_from_latex(args, callback, error_callback)
  local tex_path = args.previous --[[@as path]]
  if tex_path.exists == nil or not tex_path:exists() then
    error_callback("LaTeX file not found")
    return
  end

  -- use latex to generate a dvi
  local dvi_path = tex_path:with_suffix(".dvi")
  -- Skip if the dvi already exists
  if dvi_path:exists() then return dvi_path end

  pipeline.subprocess("latex",
    {
      args = { tex_path.path },
      stdio = { false, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      pipeline.log(ret.stdout)
      pipeline.log(ret.stderr)
      pipeline.log(args)
      if
        false
        -- and ret.code ~= 0
      then
        -- TODO

        -- latex prints error to the stdout, if this is empty, then something is fundamentally
        -- wrong with the latex binary (for example shared library error). In this case just
        -- exit the program
        if ret.stdout == "" then
          error_callback(("LaTeX exited with `%s`"):format(ret.stderr))
          return
        end

        error_callback(parse_latex_output(ret.stderr)[1])
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


-- Convert the argument, which should be the path to an SVG file, to a SVG.
-- Passes the resulting file if successful.
--
---@type pipeline_stage
function latex.generate_svg_from_dvi(args, callback, error_callback)
  local dvi_path = args.previous --[[@as path]]
  if dvi_path.exists == nil or not dvi_path:exists() then error_callback("DVI file not found") return end

  -- convert the dvi to a svg file with the woff font format
  local svg_path = dvi_path:with_suffix(".svg")

  -- Skip if the SVG already exists
  if svg_path:exists() then return svg_path end

  pipeline.subprocess("dvisvgm",
    {
      args ={ "-b", "1", "--no-fonts", "--zoom=10.0", dvi_path.path },
      stdio = { false, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      -- TODO
      pipeline.log(ret.stdout)
      pipeline.log(ret.stderr)
      pipeline.log(args)

      if ret.code ~= 0 or ret.stderr:find("error:", 1, true) ~= nil then
        -- buf = table.concat(ret.stdout, "")

        error_callback("dvisvgm error: " .. ret.stderr)
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
-- Passes the resulting file if successful.
--
---@type pipeline_stage
function latex.rasterize(args, callback, error_callback)
  local svg_path = args.previous --[[@as path]]
  if not svg_path.exists or not svg_path:exists() then error_callback("SVG file not found") return end

  -- convert the dvi to a svg file with the woff font format
  local png_path = svg_path:with_suffix(".png")

  -- Skip if the PNG already exists
  if png_path:exists() then return png_path end

  pipeline.subprocess("magick",
    {
      args ={ "-density", "600", svg_path.path, png_path.path },
      stdio = { false, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      -- TODO
      if ret.code ~= 0 then
        pipeline.log("RASTERIZE", ret)
        pipeline.log(args)
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


-- Pipe the argument (as a list of strings) into a Python interpreter,
-- Passes along the output lines if successful.
--
---@type pipeline_stage
function latex.run_python(args, callback, error_callback)
  local code = args.previous --[[@as string[] ]]

  local _, stdin = pipeline.subprocess("python",
    {
      args ={ "-" },
      stdio = { true, true, true },
      cwd = path.tempdir,
    },
    function(ret)
      if ret.code ~= 0 then
        pipeline.log(ret.stdout)
        pipeline.log(ret.stderr)
        pipeline.log(args)
        error_callback("Python error:\n" .. vim.split(ret.stderr, "\n"))
        return
      end

      local params = args.node.params
      local next_stage = nil
      if vim.list_contains(params.others, "math") then
        -- Chain into math pipeline
        params["math"] = nil
        next_stage = "#math"
      elseif vim.list_contains(params.others, "latex") then
        -- Chain into LaTeX pipeline
        params["latex"] = nil
        next_stage = "#latex"
      elseif vim.list_contains(params.others, "image") then
        -- Display image
        next_stage = "display"
      else
        -- TODO
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


-- Pipe the argument (as a list of strings) through gnuplot, targeting a PNG file.
-- Passes along the resulting LaTeX file if successful.
--
---@type pipeline_stage
function latex.gnuplot_to_png(args, callback, error_callback)
  local content = args.previous --[[@as string[] ]]
  local png_path = path.new_temp(args.node.hash, ".png")

  local preamble = ("set output '%s'\nset terminal png\n"):format(png_path)

  local _, stdin = pipeline.subprocess("gnuplot",
    {
      args ={ "-" },
      stdio = { true, false, true },
      cwd = path.tempdir,
    },
    function(ret)
      if ret.code ~= 0 then
        -- TODO:
        pipeline.log(ret.stdout)
        pipeline.log(ret.stderr)
        pipeline.log(args)
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

return latex
