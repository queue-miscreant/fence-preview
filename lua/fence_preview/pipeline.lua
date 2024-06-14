local pipeline = {
  ---@type {[string]: pipeline_stage[]}
  runners = {},
  _logs = {},
  subprocess_timeout_ms = 5000,
}

-- Declare a runner with a name. The runner should be a list of pipeline stages, or
-- a string to a pipeline stage which already exists.
--
---@param funs (pipeline_stage|string)[]
function pipeline.add_runner(name, funs)
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

-- Pipelines are basically a MonadFail.
-- The failure case should correspond to setting an error on the extmark.

---@class pipeline_input
---@field previous any
---@field node node
---@field draw_number integer

---@alias pipeline_stage fun(input: pipeline_input, callback?: fun(ret: any, maybe_defer?: string|nil), error_callback?: fun(msg: string)): any


---@param input pipeline_input
---@param stages pipeline_stage[]
local function run_pipeline(input, stages)
  if stages == nil then return end

  local function cb(e)
    local error_callback = pipeline.runners["error"][1]
    if error_callback == nil then
      print(e, input)
    else
      input.previous = e
      error_callback(input)
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

pipeline.run = run_pipeline

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

-- Wrapper around luv.spawn which automatically sets up pipes.
--
---@param process string
---@param params table The same as the second argument to luv.spawn, but with booleans instead of pipe objects.
---@param callback fun(ret: subprocess_return) A callback function which contains stdout and stderr content
---@param callback_timeout? fun() A callback function which is run if the process is still active after `pipeline.subprocess_timeout_ms`
---@return handle|nil, pipe|nil
function pipeline.subprocess(process, params, callback, callback_timeout)
  if params.stdio == nil then return nil end
  local stdio = params.stdio

  local stdin = nil
  local stdout = nil
  local stderr = nil
  if stdio[1] then stdin = vim.loop.new_pipe() --[[@as pipe]] end
  if stdio[2] then stdout = vim.loop.new_pipe() --[[@as pipe]] end
  if stdio[3] then stderr = vim.loop.new_pipe() --[[@as pipe]] end

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
