local M = {}

local sym_table_mt = {}

---@type table<storm-mode.sym, integer>
M.process_sym_to_id = setmetatable({}, sym_table_mt)
---@type table<integer, storm-mode.sym>
M.process_id_to_sym = {}

---@param self table<storm-mode.sym, integer>
---@param key storm-mode.sym
---@return integer?
sym_table_mt.__index = function(self, key)
    for k, v in pairs(self) do
        if k == key then return v end
    end
end

local sym_mt = {}

---Symbol helper class
---@class storm-mode.sym: table
---@field __sym string
---@param name string
---@return storm-mode.sym
function M.literal(name)
    local self = setmetatable({}, sym_mt)
    self.__sym = name
    return self
end

function sym_mt.__tostring(self)
    return self.__sym
end

function sym_mt.__eq(lhs, rhs)
    return lhs.__sym == rhs.__sym
end

return M
