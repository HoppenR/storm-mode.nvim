local M = {}

-- For `Lsp.process_sym_to_id` and `Lsp.process_id_to_sym`:
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

---Decode the message, returns nil if the message is not complete
---@param message string
---@return string | storm-mode.lsp.message
---@return string unprocessed
function M.dec_message(message)
    if message:byte(1) ~= 0x0 then
        -- Read up until a null byte
        local stop = message:find(0x0)
        return message:sub(1, stop), stop and message:sub(stop) or ''
    end

    local bufsz, msgstr = M.dec_number(message:sub(2))
    if bufsz > #msgstr then
        return '', message
    end

    return M.dec_message_body(msgstr), msgstr:sub(bufsz + 1)
end

---Decode the message body
---@param msgstr string
---@return storm-mode.lsp.message
function M.dec_message_body(msgstr)
    ---@type storm-mode.lsp.message
    local ret = {}
    local loops = 1

    while true do
        loops = loops + 1
        local tag = msgstr:byte(1)

        if tag == 0x0 then
            return ret
        elseif tag == 0x1 then
            msgstr = msgstr:sub(2)
        else
            assert(false, tag)
        end

        tag = msgstr:byte(1)
        msgstr = msgstr:sub(2)

        if tag == 0x0 then
            -- skip...
        elseif tag == 0x2 then
            local num
            num, msgstr = M.dec_number(msgstr)
            table.insert(ret, num)
        elseif tag == 0x3 then
            local str
            str, msgstr = M.dec_string(msgstr)
            table.insert(ret, str)
        elseif tag == 0x4 or tag == 0x5 then
            local symb
            symb, msgstr = M.dec_sym(msgstr, tag == 0x5)
            table.insert(ret, symb)
        else
            assert(false, tag)
        end
    end
end

---Decode 4 bytes into a number (32-bit unsigned, big-endian order)
---@param msgstr string
---@return integer, string
function M.dec_number(msgstr)
    local b1, b2, b3, b4 = msgstr:byte(1, 5)
    return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4, msgstr:sub(5)
end

---@param msgstr string
---@return string, string
function M.dec_string(msgstr)
    local sz
    sz, msgstr = M.dec_number(msgstr)
    return msgstr:sub(1, sz), msgstr:sub(sz + 1)
end

---@param msgstr string
---@param is_known boolean
---@return storm-mode.sym, string
function M.dec_sym(msgstr, is_known)
    local sym_id
    sym_id, msgstr = M.dec_number(msgstr)

    if is_known then
        return Lsp.process_id_to_sym[sym_id], msgstr
    end

    local sym_name
    sym_name, msgstr = M.dec_string(msgstr)
    local new_sym = sym(sym_name)
    Lsp.process_sym_to_id[sym_name] = sym_id
    Lsp.process_id_to_sym[sym_id] = new_sym
    return new_sym, msgstr
end

return M
