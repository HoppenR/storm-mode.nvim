local M = {}

local sym_table_mt = {}

---@type table<storm-mode.sym, integer>
M.sym_to_symid = setmetatable({}, sym_table_mt)
---@type table<integer, storm-mode.sym>
M.symid_to_sym = {}

---@param self table<storm-mode.sym, integer>
---@param key storm-mode.sym
---@return integer?
sym_table_mt.__index = function(self, key)
    for k, v in pairs(self) do
        if k == key then return v end
    end
end

---Symbol helper class to emulate elisp symbols, whose value is their own name
---@class storm-mode.sym
---@field private __sym string
local sym_mt = {}
sym_mt.__index = sym_mt

---@param name string
---@return storm-mode.sym
function M.literal(name)
    ---@type storm-mode.sym
    local self = { __sym = name }
    return setmetatable(self, sym_mt)
end

---@param self storm-mode.sym
---@return string
function sym_mt.__tostring(self)
    return self.__sym
end

---@param lhs storm-mode.sym
---@param rhs storm-mode.sym
---@return boolean
function sym_mt.__eq(lhs, rhs)
    return lhs.__sym == rhs.__sym
end

return M
