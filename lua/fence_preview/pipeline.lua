local path = require "fence_preview.polyfill.path"
local delimit = require "fence_preview.delimit"
local settings = require "fence_preview.settings"

local pipeline = {
  ---@type {[string]: Pipeline}
  runners = {},
}


-- Declare a pipeline with a name. The should be a list containing pipeline stages, or
-- a string to a pipeline stage which already exists.
--
---@param name string Name of the pipleine stage
---@param funs (PipelineStage | string)[] A list of pipline stages to associate to a name
---@param manual? boolean
function pipeline.define(name, funs, manual)
  ---@type PipelineStage[]
  local ret = {}
  local had_string = false

  for _, j in pairs(funs) do
    if type(j) == "string" then
      local lookup_stages = pipeline.runners[j]
      if lookup_stages == nil then
        error(
          ("Could not create pipeline `%s`. Stage `%s` does not exist")
            :format(name, j)
        )
      end
      vim.list_extend(ret, lookup_stages.stages)
      had_string = true
    else
      if had_string then
        error("Cannot create a pipeline with named stage in non-terminal position")
      end
      table.insert(ret, j)
    end
  end
  pipeline.runners[name] = {
    stages = ret,
    manual = not not manual,
  }
end


-- Run a pipeline -- a series of functions which are chained together with callbacks.
-- Should an error occur inside a function, the runner "error" (defined with `pipeline.define`)
-- is invoked.
--
---@param input PipelineInput
---@param stages PipelineStage[]
function pipeline.run(input, stages)
  -- Simple error callback wrapper to run the stage named `error`, if one exists
  local function cb(e)
    local error_callback = pipeline.runners["error"]
    if error_callback == nil then
      print(e, input)
    else
      input.previous = e
      error_callback.stages[1](input)
    end
  end

  local stage = 0
  local function linker(output, maybe_defer)
    local safe = true
    local next_value = output
    -- Keep trying to run callbacks as long as we're synchronous
    while true do
      if not safe then cb(next_value) return end

      -- Advance the pipeline by a stage if we haven't been deferred to another
      -- Otherwise, reset and get new stages
      if maybe_defer == nil then
        stage = stage + 1
      elseif type(maybe_defer) == "string" then
        stage = 1
        stages = pipeline.runners[maybe_defer].stages
      end
      ---@type PipelineStage
      local next_stage = stages[stage]
      if next_stage == nil then return end

      -- Prepare the input and call the stage on it
      input.previous = next_value
      safe, next_value, maybe_defer = pcall(function() return next_stage(input, linker, cb) end)

      if next_value == nil then return end
    end
  end

  linker(input.previous)
end


-- Attempt to run pipelines on a node.
-- File nodes attempt to find and run a pipeline based on the suffix of the path
-- (e.g., ".tex"). If no pipeline is found, it calls the "display" pipeline.
--
-- Fence nodes attempt to find and run a pipeline based on the filetype, preceded
-- by a "#" (e.g., "#python"). If no pipeline exists, it will not be run.
--
---@param node Node A node to run through a pipeline
---@param manual? boolean
function pipeline.pipe_node(node, manual)
  ---@type string
  local stage_name
  ---@type string[] | string
  local value = nil

  -- File nodes just run the pipeline `.{ext}`, or image display if none exists
  if node.type == "file" then
    ---@cast node FileNode
    value = path.new(node.filename)
    if value.suffix == nil then return nil end

    stage_name = value.suffix
    -- Pipeline exists for suffix
    if
      pipeline.runners[stage_name] == nil
      and vim.tbl_contains(settings.preview_extensions, stage_name)
    then
      stage_name = "display"
    end
  -- Fenced content with a filetype runs the pipeline `#{ft}`
  else
    ---@cast node FenceNode
    stage_name = "#" .. node.params.filetype
    value = node.content
  end

  -- TODO: Manual/automatic pipelines should be configured via setting variables
  local runner = pipeline.runners[stage_name]
  if
    runner ~= nil
    -- This pipeline must be manually triggered
    and (manual or not runner.manual)
  then
    pipeline.run(
      {
        previous = value,
        node = node,
      },
      runner.stages
    )
  end
end


-- Attempt to run pipelines on a list of nodes.
-- The same semantics to `pipeline.pipe_nodes` applies, but over a table of nodes.
--
---@param nodes Node[] A node to run through a pipeline
---@param manual? boolean
function pipeline.pipe_nodes(nodes, manual)
  for _, node in ipairs(nodes) do
    pipeline.pipe_node(node, manual)
  end
end


-- Also in method form
delimit.node_metatable.pipe = pipeline.pipe_node

return pipeline
