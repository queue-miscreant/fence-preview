local pipeline = require("fence_preview.pipeline")

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
  -- tempdir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
  tempdir = ".",
}


-- local latex_path = shutil.which("latex")
-- if latex_path == nil then
--   error("Could not find LaTeX installation!")
-- end

-- local dvisvgm_path = shutil.which("dvisvgm")
-- if dvisvgm_path == nil then
--   error("Could not find dvisvgm!")
-- end

---@alias path string

local with_suffix
local join_path
if vim.fs ~= nil then
  ---@param path string
  ---@param suffix string
  ---@return string
  function with_suffix(path, suffix)
    local name = (vim.fs.basename(path)):match("([^.]*)%.?(%w*)$")
    local parent = vim.fs.dirname(path)
    if parent == "." then
      return name .. suffix
    end
    return vim.fs.joinpath(parent, name .. suffix)
  end

  join_path = vim.fs.joinpath
else
  join_path = function(...)
    return vim.fn.simplify(table.concat({ ... }, "/"))
  end
end

-- latex.with_suffix = with_suffix


---@type pipeline_stage
function latex.write_math(args, callback, error_callback)
  -- create a new tex file containing the equation
  local tex_path = join_path(latex.tempdir, with_suffix(args.node.hash, ".tex"))

  -- No need to write the file again, continue with pipeline
  if vim.fn.filereadable(tex_path) ~= 0 then
    callback(tex_path)
    return
  end
  -- Bad argument
  if
    type(args.previous) ~= "table"
    or type(args.previous[1]) ~= "string"
  then
    vim.print(args)
    error_callback("Cannot write math file: invalid argument")
    return
  end

  local file = io.open(tex_path, "w")
  if file == nil then
    -- TODO
    error_callback(("Could not open file `%s`"):format(tex_path))
    return
  end
  vim.print(args.previous)
  file:write(MATH_START, unpack(args.previous)) ---@diagnostic disable-line
  file:write(MATH_END)
  file:close()

  callback(tex_path)
end


-- Parse output from LaTeX process stdout into a more digestable form
-- TODO: Look at latex output more clearly
--
---@param buf string
local function parse_latex_output(buf)
  local err = { "", "", nil }

  for _, elm in ipairs(vim.split(buf, "\n")) do
    ---@cast elm string
    if elm:find("! ", 1, true) ~= nil then
      err[1] = elm
    elseif elm:find("l.", 1, true) ~= nil and elm:find("Emergency stop", 1, true) == -1 then
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


---@type pipeline_stage
function latex.generate_dvi_from_latex(args, callback, error_callback)
  local path = args.previous --[[@as path]]
  if vim.fn.filereadable(path) == 0 then error_callback("LaTeX file not found") return end

  -- use latex to generate a dvi
  local dvi_path = with_suffix(path, ".dvi")
  -- Skip if the dvi already exists
  if vim.fn.filereadable(dvi_path) ~= 0 then callback(dvi_path) return end

  pipeline.subprocess("latex",
    {
      args = { with_suffix(path, ".tex") },
      stdio = { false, true, true },
      cwd = latex.tempdir,
    },
    function(ret)
      if
        false
        -- and ret.code ~= 0
      then
        -- TODO
        local buf = table.concat(ret.stdout, "")

        -- latex prints error to the stdout, if this is empty, then something is fundamentally
        -- wrong with the latex binary (for example shared library error). In this case just
        -- exit the program
        if buf == "" then
          buf = table.concat(ret.stderr, "")
          error_callback(("Latex exited with `%s`"):format(buf))
          return
        end

        error_callback(parse_latex_output(buf))
        return
      end

      callback(with_suffix(path, ".dvi"))
    end
  )
  -- Extra args from Rust:
  --
  -- .arg("--jobname").arg(&dvi_path)
  -- .expect("Could not spawn latex");
end

---@type pipeline_stage
function latex.generate_svg_from_dvi(args, callback, error_callback)
  local path = args.previous --[[@as path]]
  if vim.fn.filereadable(path) == 0 then error_callback("DVI file not found") return end

  -- convert the dvi to a svg file with the woff font format
  local svg_path = with_suffix(path, ".svg")

  -- Skip if the SVG already exists
  if vim.fn.filereadable(svg_path) ~= 0 then callback(svg_path) return end

  pipeline.subprocess("dvisvgm",
    {
      args ={ "-b", "1", "--no-fonts", "--zoom=1.0", tostring(path) },
      stdio = { false, true, true },
      cwd = latex.tempdir,
    },
    function(ret)
      -- TODO
      local buf = table.concat(ret.stderr, "")
      if ret.code ~= 0 or buf:find("error:") ~= -1 then
        buf = table.concat(ret.stdout, "")

        error_callback(buf)
        return
      end

      callback(svg_path)
    end
  )
end

return latex
