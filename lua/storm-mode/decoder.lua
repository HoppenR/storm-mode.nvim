local M = {}

-- For `Lsp.process_sym_to_id` and `Lsp.process_id_to_sym`:
local Sym = require('storm-mode.sym')
local sym = require('storm-mode.sym').literal

---Decode the message, returns nil if the message is not complete
---@param message string
---@return string | storm-mode.lsp.message | nil payload?
---@return string unprocessed
function M.dec_message(message)
    if #message == 0 then
        return nil, ''
    end

    if message:byte(1) ~= 0x0 then
        -- Read up until a null byte
        local stop = message:find('\0')
        if stop then
            return message:sub(1, stop - 1), message:sub(stop)
        end
        return message, ''
    end

    local it = vim.iter(vim.gsplit(message, '')):skip(1) -- Skip first null byte

    if M.dec_number(it) > #message - 5 then
        -- Incomplete message, return the original
        return nil, message
    end

    return M.dec_message_body(it), it:join('')
end

---Decode the message body
---@param it Iter
---@return storm-mode.lsp.message
function M.dec_message_body(it)
    ---@type storm-mode.lsp.message
    local ret = {}

    while true do
        local tag = string.byte(it:next())

        if tag == 0x0 then
            return ret
        end
        assert(tag == 0x1, tag, 'invalid tag')

        tag = string.byte(it:next())

        if tag == 0x0 then
            -- Can't insert nil into a table in lua...
            table.insert(ret, sym 'nil')
        elseif tag == 0x2 then
            table.insert(ret, M.dec_number(it))
        elseif tag == 0x3 then
            table.insert(ret, M.dec_string(it))
        elseif tag == 0x4 or tag == 0x5 then
            table.insert(ret, M.dec_sym(it, tag == 0x5))
        else
            assert(false, 'invalid tag')
        end
    end
end

---Decode 4 bytes into a number (32-bit unsigned, big-endian order)
---@param it Iter
---@return integer
function M.dec_number(it)
    local acc = 0
    for _ = 1, 4 do
        acc = acc * 0x10 + string.byte(it:next())
    end
    return acc
end

---@param it Iter
---@return string
function M.dec_string(it)
    local sz = M.dec_number(it)
    local acc = ''
    for _ = 1, sz do
        local next = it:next()
        acc = acc .. next
    end
    return acc
end

---@param it Iter
---@param is_known boolean
---@return storm-mode.sym
function M.dec_sym(it, is_known)
    local sym_id = M.dec_number(it)

    if is_known then
        return Sym.process_id_to_sym[sym_id]
    end

    local sym_name = M.dec_string(it)
    local new_sym = sym(sym_name)
    Sym.process_sym_to_id[sym_name] = sym_id
    Sym.process_id_to_sym[sym_id] = new_sym
    return new_sym
end

return M
