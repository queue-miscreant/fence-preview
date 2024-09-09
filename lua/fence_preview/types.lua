---@class PipelineExtmark
---@field id integer
---@field type string

---@alias ExtmarkModuleAdd fun(node: Node, path: Path): integer
---@alias ExtmarkModuleRemove fun(extmark_id: integer)
---@alias ExtmarkModuleIterIDs fun(): (fun(): integer?, integer?)
---@alias ExtmarkModuleRedraw fun(force?: boolean)
---@alias ExtmarkModuleDump fun(extmark_id_to_node: {[string]: Node})

---@class ExtmarkModule
---@field name string
---@field add ExtmarkModuleAdd
---@field remove ExtmarkModuleRemove
---@field iter_ids ExtmarkModuleIterIDs
---@field redraw? ExtmarkModuleRedraw
---@field dump? ExtmarkModuleDump

---@class BufferData
---@field nodes (Node)[]
---@field node_id_to_extmarks {[string]: PipelineExtmark}

---@class PipelineInput
---@field previous any
---@field node Node

---@alias PipelineCallback fun(ret: any, maybe_defer?: string|nil)
---@alias PipelineStage fun(input: PipelineInput, callback?: PipelineCallback, error_callback?: fun(msg: string)): any, string?

---@class Pipeline
---@field stages PipelineStage[]
---@field manual boolean

---@class FenceParams
---@field filetype string
---@field height? integer
---@field content string[]
---@field others string[]

---@class FenceNode
---@field type "fence"
---@field content string[]
---@field params FenceParams
---@field range [integer, integer]
---@field id integer
---@field hash string
---@field buffer integer
---@field draw_number? integer
---@field logs string[]
---
---@field is_line_inside? fun(self: Node, line: integer): boolean
---@field log? fun(self: FenceNode, ...: any)
---@field log_self? fun(self: FenceNode)
---@field clear_logs? fun(self: FenceNode)

---@class FileNode
---@field type "file"
---@field filename string
---@field range [integer, integer]
---@field id integer
---@field hash string
---@field buffer integer
---@field draw_number? integer
---@field logs string[]
---
---@field is_line_inside? fun(self: Node, line: integer): boolean
---@field log? fun(self: FileNode, ...: any)
---@field log_self? fun(self: FileNode)
---@field clear_logs? fun(self: FileNode)

---@alias Node FenceNode|FileNode
