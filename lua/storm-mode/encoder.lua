local M = {}

local Bit = require('bit')

M.process_next_id = 1 ---@type integer
M.process_sym_to_id = {} ---@type table<storm-mode.Sym, integer>
M.process_id_to_sym = {} ---@type table<integer, storm-mode.Sym>

---Encode the message header and body
---@param message storm-mode.lsp.message
---@return string
function M.enc_message(message)
    local encoded_body = M.enc_message_body(message)
    return string.char(0x0) .. M.enc_number(#encoded_body) .. encoded_body
end

---Encode the message body
---@param message storm-mode.lsp.message
---@return string
function M.enc_message_body(message)
    local ret = ''
    for _, val in ipairs(message) do
        ret = ret .. string.char(0x1)
        if type(val) == 'table' then
            ret = ret .. M.enc_sym(val --[[@as storm-mode.Sym]])
        elseif type(val) == 'number' then
            ret = ret .. string.char(0x2) .. M.enc_number(val)
        elseif type(val) == 'string' then
            ret = ret .. string.char(0x3) .. M.enc_string(val)
        else
            assert(false, 'Unexpected val type: ' .. type(val))
        end
    end
    return ret .. string.char(0x0)
end

---Encode message as 4 bytes (32-bit unsigned, big-endian order)
---@param num number
---@return string
function M.enc_number(num)
    return table.concat {
        string.char(Bit.band(Bit.rshift(num, 24), 0xFF)),
        string.char(Bit.band(Bit.rshift(num, 16), 0xFF)),
        string.char(Bit.band(Bit.rshift(num, 8), 0xFF)),
        string.char(Bit.band(num, 0xFF)),
    }
end

---Prepend message with its length
---@param str string
---@return string
function M.enc_string(str)
    return M.enc_number(#str) .. str
end

---Encode symbol, new (0x4) or old (0x5)
---@param sym storm-mode.Sym
---@return string
function M.enc_sym(sym)
    local id = M.process_sym_to_id[sym]
    if id then
        return string.char(0x5) .. M.enc_number(id)
    else
        id = M.process_next_id
        M.process_next_id = M.process_next_id + 1
        M.process_sym_to_id[sym] = id
        M.process_id_to_sym[id] = sym
        return string.char(0x4) .. M.enc_number(id) .. M.enc_string(tostring(sym))
    end
end

return M
