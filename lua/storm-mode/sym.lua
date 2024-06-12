local M = {}

---Symbol helper class
---@class storm-mode.sym : table
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
