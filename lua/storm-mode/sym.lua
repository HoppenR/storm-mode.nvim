local M = {}

---Symbol ids are shared by both directions of the protocol: a symbol declared
---by either side (tag 0x04) may be referred to by id (tag 0x05) by both.
---Keyed by symbol name.
---@type table<string, integer>
M.sym_to_symid = {}
---@type table<integer, storm-mode.sym>
M.symid_to_sym = {}

---Forget all symbols; call when a new Storm process starts
function M.reset()
    M.sym_to_symid = {}
    M.symid_to_sym = {}
end

local sym_mt = {}

---Symbol helper class
---@class storm-mode.sym
---@field protected __sym string
---@param name string
---@return storm-mode.sym
function M.literal(name)
    local self = setmetatable({}, sym_mt)
    self.__sym = name
    return self
end

---@param value any
---@return boolean
function M.is_sym(value) return type(value) == 'table' and getmetatable(value) == sym_mt end

function sym_mt.__tostring(self) return self.__sym end

function sym_mt.__eq(lhs, rhs) return lhs.__sym == rhs.__sym end

return M
