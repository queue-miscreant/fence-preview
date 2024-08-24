-- fence_preview.polyfill.path
--
-- Object-oriented style polyfills for vim.fs path manipulations

---@class Path
---@field path string
---@field suffix string
---@field basename string
---
---@field exists fun(path: Path): boolean
---@field with_suffix fun(path: Path, suffix: string): Path
---@field parent fun(path: Path): Path
---@field relative_to fun(path: Path): Path

local Path = {
  tempdir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
}
Path.__index = Path

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


-- Create a new path from the string "target".
-- The path will be attempted to be converted to an absolute path.
--
---@param target string
---@return Path
function Path.new(target)
  target = normalize(target)
  local base = basename(target)
  local no_suffix, suffix = base:match("([^.]*)(%.?%w*)$")

  local ret = {
    path = target,
    _no_suffix = no_suffix,
    suffix = suffix,
    basename = base,
  }
  setmetatable(ret, Path)

  return ret
end


-- Create a new path in the temporary directory.
--
---@param name string
---@param suffix? string
---@return Path
function Path.new_temp(name, suffix)
  local base = name
  local no_suffix = name
  if suffix == nil then
    no_suffix, suffix = base:match("([^.]*)(%.?%w*)$")
  end

  local ret = {
    path = Path.tempdir .. "/" .. name .. suffix,
    _no_suffix = no_suffix,
    suffix = suffix,
    basename = base,
  }
  setmetatable(ret, Path)

  return ret
end


-- Create a new path wrapping the parent of the current one.
--
---@return Path
function Path:parent()
  local dir = dirname(self.path)
  local ret = {
    path = dirname,
    _no_suffix = dirname,
    suffix = "",
    basename = basename(dir)
  }
  setmetatable(ret, Path)

  return ret
end


-- Create a new path with a different suffix ("extension").
--
---@param suffix string
---@return Path
function Path:with_suffix(suffix)
  local dir = dirname(self.path)
  local base = self._no_suffix .. suffix
  local ret = {
    path = joinpath(dir, base),
    _no_suffix = self._no_suffix,
    suffix = suffix,
    basename = base
  }
  setmetatable(ret, Path)

  return ret
end


-- Convert a relative path to an absolute one relative to `cwd`.
-- If the path is already absolute, this does nothing.
--
---@param cwd Path|string
---@return Path
function Path:relative_to(cwd)
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
  setmetatable(ret, Path)

  return ret
end


-- Test the existence of the path.
--
---@return boolean
function Path:exists()
  return vim.fn.filereadable(self.path) ~= 0
end

return Path
