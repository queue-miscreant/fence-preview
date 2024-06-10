local pipeline = {
  runners = {},
  subprocess_timeout_ms = 5000,
}

function pipeline.add_runner(name, fun)
  pipeline.runners[name] = fun
end

-- Pipelines are basically a MonadFail.
-- The failure case should correspond to setting an error on the extmark.

---@class pipeline_input
---@field previous any
---@field node node

---@alias pipeline_stage fun(input: pipeline_input, callback: fun(ret: any), error_callback: fun(any))


---@param input pipeline_input
local function run_pipeline(input, stages, error_callback)
  if error_callback == nil then error_callback = vim.print end

  local stage = 1
  local function linker(output)
    stage = stage + 1
    local next_stage = stages[stage]
    if next_stage == nil then return end
    next_stage(
      {
        previous = output,
        node = input.node
      },
      linker,
      error_callback
    )
  end

  stages[1](input, linker, error_callback)
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
---@field stdout string[]
---@field stderr string[]

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
        stdout = stdout_content,
        stderr = stderr_content,
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
