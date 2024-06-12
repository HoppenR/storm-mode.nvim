local M = {}

M.process_sym_to_id = {} ---@type table<storm-mode.sym, integer>
M.process_id_to_sym = {} ---@type table<integer, storm-mode.sym>

setmetatable(M.process_sym_to_id, {
    ---@param tbl table<storm-mode.sym, integer>
    ---@param key storm-mode.sym
    ---@return string?
    __index = function(tbl, key)
        for k, v in pairs(tbl) do
            if k.__sym == key.__sym then
                return v
            end
        end
        return nil
    end
})

---Symbol helper class
---@class storm-mode.sym: table
---@field __sym string
---@param name string
---@return storm-mode.sym
function M.literal(name)
    local self = setmetatable({}, {
        __tostring = function(self) return self.__sym end,
    })
    self.__sym = name
    return self
end

return M
