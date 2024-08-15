-- fence_preview.path.lua
--
-- Object-oriented style polyfills for vim.fs path manipulations

local path = {
  tempdir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
}

---@type fun(path: string): string
local normalize
---@type fun(path: string): string
local basename
---@type fun(path: string): string
local dirname
---@type fun(path1: string, path2: string): string
local joinpath
if vim.fs == nil then
  -- TODO: This doesn't actually work!
  -- These functions need to be available in a loop callback
  function normalize(file_path)
    -- TODO: not quite; normalize should keep absolute paths as absolute and relative paths as relative
    -- Note that ~ is "absolute" in this sense
    return vim.fn.fnamemodify(file_path, ":p")
  end
  function basename(file_path)
    return vim.fn.fnamemodify(file_path, ":t")
  end
  function dirname(file_path)
    return vim.fn.fnamemodify(file_path, ":h")
  end
  function joinpath(path1, path2)
    return path1 .. "/" .. path2
  end
else
  normalize = vim.fs.normalize
  basename = vim.fs.basename
  dirname = vim.fs.dirname
  joinpath = vim.fs.joinpath
end

---@class path
---@field path string
---@field suffix string
---@field basename string
---
---@field exists fun(path: path): boolean
---@field with_suffix fun(path: path, suffix: string): path
---@field parent fun(path: path): path
---@field relative_to fun(path: path): path

-- Create a new path from the string "target".
-- The path will be attempted to be converted to an absolute path.
--
---@param target string
---@return path
function path.new(target)
  target = normalize(target)
  local base = basename(target)
  local no_suffix, suffix = base:match("([^.]*)(%.?%w*)$")

  local ret = {
    path = target,
    _no_suffix = no_suffix,
    suffix = suffix,
    basename = base,
  }
  setmetatable(ret, path)
  path.__index = path

  return ret
end


-- Create a new path in the temporary directory.
--
---@param name string
---@param suffix? string
---@return path
function path.new_temp(name, suffix)
  local base = name
  local no_suffix = name
  if suffix == nil then
    no_suffix, suffix = base:match("([^.]*)(%.?%w*)$")
  end

  local ret = {
    path = path.tempdir .. "/" .. name .. suffix,
    _no_suffix = no_suffix,
    suffix = suffix,
    basename = base,
  }
  setmetatable(ret, path)
  path.__index = path

  return ret
end

---@return string
function path:__tostring()
  return self.path
end

---@return path
function path:parent()
  local dir = dirname(self.path)
  local ret = {
    path = dirname,
    _no_suffix = dirname,
    suffix = "",
    basename = basename(dir)
  }
  setmetatable(ret, path)
  path.__index = path

  return ret
end

---@param suffix string
---@return path
function path:with_suffix(suffix)
  local dir = dirname(self.path)
  local base = self._no_suffix .. suffix
  local ret = {
    path = joinpath(dir, base),
    _no_suffix = self._no_suffix,
    suffix = suffix,
    basename = base
  }
  setmetatable(ret, path)
  path.__index = path

  return ret
end

---@param cwd path|string
---@return path
function path:relative_to(cwd)
  if self.path:sub(1,1) == "/" then
    return self
  end
  if type(cwd) ~= "string" then
    cwd = cwd.path
  else
    -- TODO: only if directory
    cwd = dirname(cwd)
  end

  local ret = {
    path = joinpath(cwd, self.path),
    _no_suffix = self._no_suffix,
    suffix = self.suffix,
    basename = self.basename
  }
  setmetatable(ret, path)
  path.__index = path

  return ret
end

---@return boolean
function path:exists()
  return vim.fn.filereadable(self.path) ~= 0
end

return path
