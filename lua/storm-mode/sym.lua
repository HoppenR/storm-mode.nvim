local M = {}

---Symbol helper class
---@class storm-mode.Sym
---@field __sym string
---@param name string
---@return storm-mode.Sym
function M.literal(name)
    local self = setmetatable({}, {
        __tostring = function(self) return self.__sym end,
    })
    self.__sym = name
    return self
end

return M
