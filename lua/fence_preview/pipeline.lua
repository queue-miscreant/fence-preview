local path = require "fence_preview.path"

local pipeline = {
  ---@type {[string]: pipeline_stage[]}
  runners = {},
  _logs = {},
  subprocess_timeout_ms = 5000,
}

-- Declare a pipeline with a name. The  should be a list containing pipeline stages, or
-- a string to a pipeline stage which already exists.
--
---@param funs (pipeline_stage|string)[] A list of pipline stages to associate to a name
function pipeline.define(name, funs)
  local ret = {}
  for _, j in pairs(funs) do
    if type(j) == "string" then
      local lookup_stages = pipeline.runners[j]
      if lookup_stages == nil then error(("Could not create pipeline `%s`"):format(j)) end
      vim.list_extend(ret, lookup_stages)
    else
      table.insert(ret, j)
    end
  end
  pipeline.runners[name] = ret
end

function pipeline.log(...)
  local args = { ... }
  for _, entry in ipairs(args) do
    if type(entry) ~= "string" then
      entry = vim.inspect(entry)
    end
    vim.list_extend(pipeline._logs, vim.split(entry, "\n"))
  end
end

---@class pipeline_input
---@field previous any
---@field node node
---@field draw_number integer

---@alias pipeline_callback fun(ret: any, maybe_defer?: string|nil)
---@alias pipeline_stage fun(input: pipeline_input, callback?: pipeline_callback, error_callback?: fun(msg: string)): any, string?

-- Run a pipeline -- a series of functions which are chained together with callbacks.
-- Should an error occur inside a function, the runner "error" (defined with `pipeline.define`)
-- is invoked.
--
---@param input pipeline_input
---@param stages pipeline_stage[]
function pipeline.run(input, stages)
  if stages == nil then return end

  local function cb(e)
    local error_callback = pipeline.runners["error"]
    if error_callback == nil then
      print(e, input)
    else
      input.previous = e
      error_callback[1](input)
    end
  end

  local stage = 0
  local function linker(output, maybe_defer)
    local safe = true
    local next_value = output
    -- Keep trying to run callbacks as long as we're synchronous
    while true do
      if not safe then cb(next_value) return end
      if maybe_defer == nil then
        stage = stage + 1
      elseif type(maybe_defer) == "string" then
        stage = 1
        stages = pipeline.runners[maybe_defer]
      end
      ---@type pipeline_stage
      local next_stage = stages[stage]
      if next_stage == nil then return end

      input.previous = next_value
      safe, next_value, maybe_defer = pcall(function() return next_stage(input, linker, cb) end)

      if next_value == nil then return end
    end
  end

  linker(input.previous)
end


-- Attempt to run pipelines on a list of nodes.
-- Nodes which are simple files will attempt to run a pipeline based on the suffix of the path
-- (e.g., ".tex"). If no pipeline is found, it calls the "display" pipeline.
--
-- Nodes which contain fenced content attempt to run a pipeline based on the filetype, preceded
-- by a "#" (e.g., "#python"). If no pipeline exists, it will not be run.
--
---@param nodes node[] A list of nodes, each of which gets run through a pipeline
---@param draw_number integer A node-independed number passed along the pipeline
function pipeline.pipe_nodes(nodes, draw_number)
  for _, node in pairs(nodes) do
    ---@type string
    local stage_name
    ---@type string[] | string
    local value = nil
    if node.type == "file" then
      ---@cast node file_node
      value = path.new(node.filename)
      if value.suffix == nil then return nil end

      stage_name = value.suffix
      -- Pipeline exists for suffix
      if pipeline.runners[stage_name] == nil then
        stage_name = "display"
      end
    else
      ---@cast node fence_node
      stage_name = "#" .. node.params.filetype
      value = node.content
    end

    pipeline.run(
      {
        previous = value,
        node = node,
        draw_number = draw_number
      },
      pipeline.runners[stage_name]
    )
  end
end

---@class handle

---@class pipe
---@field write fun(self: pipe, input: string|string[], callback?: fun(err: string|nil))
---@field read_start fun(self: pipe, callback: fun(err: string|nil, data: string|nil))
---@field shutdown fun(self: pipe, callback?: fun())

---@class subprocess_return
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string

---@class almost_luv_params
---@field args string[]
---@field stdio? [boolean, boolean, boolean]
---@field cwd? string

-- Wrapper around luv.spawn which automatically sets up pipes.
-- TODO: Maybe wrap vim.spawn instead of luv.spawn?
--
---@param process string
---@param params almost_luv_params The same as the second argument to luv.spawn, but with booleans instead of pipe objects.
---@param callback fun(ret: subprocess_return) A callback function which contains stdout and stderr content
---@param callback_timeout? fun() A callback function which is run if the process is still active after `pipeline.subprocess_timeout_ms`
---@return handle|nil, pipe|nil
function pipeline.subprocess(process, params, callback, callback_timeout)
  if params.stdio == nil then return nil end
  local stdio = params.stdio

  local stdin = nil
  local stdout = nil
  local stderr = nil
  if stdio then
    if stdio[1] then stdin = vim.loop.new_pipe() --[[@as pipe]] end
    if stdio[2] then stdout = vim.loop.new_pipe() --[[@as pipe]] end
    if stdio[3] then stderr = vim.loop.new_pipe() --[[@as pipe]] end
  end

  ---@diagnostic disable-next-line
  params.stdio = { stdin, stdout, stderr }

  local stdout_content = {}
  local stderr_content = {}
  local finished = false

  local handle = vim.loop.spawn(process,
    params,
    function(code, signal)
      if stdin then stdin:shutdown() end
      finished = true
      callback{
        code = code,
        signal = signal,
        stdout = table.concat(stdout_content, ""),
        stderr = table.concat(stderr_content, "")
      }
    end
  )

  if stdout ~= nil then
    stdout:read_start(function(err, data)
      assert(not err, err)
      if data ~= nil then table.insert(stdout_content, data) end
    end)
  end

  if stderr ~= nil then
    stderr:read_start(function(err, data)
      assert(not err, err)
      if data ~= nil then table.insert(stderr_content, data) end
    end)
  end

  local timeout_timer = vim.loop.new_timer()
  timeout_timer:start(pipeline.subprocess_timeout_ms, 0, function()
    local function close()
      if not finished then
        handle:close()
        if callback_timeout ~= nil then
          callback_timeout()
        end
      end
    end
    if stdin then
      stdin:shutdown(close)
    else
      close()
    end
  end)

  return handle, stdin
end

return pipeline
