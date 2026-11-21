local M = {}

local Sym = require('storm-mode.sym')

M._next_symid = 1

---Encode as 4 bytes (32-bit unsigned, big-endian order)
---@param num integer
---@return string
function M.enc_number(num)
    return string.char(
        math.floor(num / 2 ^ 24) % 256,
        math.floor(num / 2 ^ 16) % 256,
        math.floor(num / 2 ^ 8) % 256,
        num % 256
    )
end

---Prefix a string with its length
---@param str string
---@return string
function M.enc_string(str) return M.enc_number(#str) .. str end

---Encode symbol, new (0x4) or old (0x5)
---@param sym storm-mode.sym
---@return string
function M.enc_sym(sym)
    local name = tostring(sym)
    local symid = Sym.sym_to_symid[name]
    if symid then return string.char(0x5) .. M.enc_number(symid) end
    symid = M._next_symid
    M._next_symid = M._next_symid + 1
    Sym.sym_to_symid[name] = symid
    Sym.symid_to_sym[symid] = sym
    return string.char(0x4) .. M.enc_number(symid) .. M.enc_string(name)
end

local enc_list

---@param val storm-mode.sexp
---@param out string[]
local function enc_value(val, out)
    local t = type(val)
    if val == vim.NIL then
        out[#out + 1] = string.char(0x0)
    elseif t == 'number' then
        out[#out + 1] = string.char(0x2) .. M.enc_number(val)
    elseif t == 'string' then
        out[#out + 1] = string.char(0x3) .. M.enc_string(val)
    elseif Sym.is_sym(val) then
        out[#out + 1] = M.enc_sym(val --[[@as storm-mode.sym]])
    elseif t == 'table' then
        enc_list(val, out)
    else
        error('Unexpected val type: ' .. t)
    end
end

---@param list storm-mode.sexp.list
---@param out string[]
function enc_list(list, out)
    for _, val in ipairs(list) do
        out[#out + 1] = string.char(0x1)
        enc_value(val, out)
    end
    enc_value(list.tail or vim.NIL, out)
end

---Encode the message body
---@param message storm-mode.lsp.message
---@return string
function M.enc_message_body(message)
    local out = {}
    enc_list(message, out)
    return table.concat(out)
end

---Encode the message header and body
---@param message storm-mode.lsp.message
---@return string
function M.enc_message(message)
    local encoded_body = M.enc_message_body(message)
    return string.char(0x0) .. M.enc_number(#encoded_body) .. encoded_body
end

return M
