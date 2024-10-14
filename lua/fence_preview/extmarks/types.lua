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

---@alias HLPair [string, string]

---@class VirtTextArgs
---@field virt_text HLPair[]
---@field virt_text_pos string

---@class VirtLinesArgs
---@field virt_lines HLPair[][]
