local M = {}

local Sym = require('storm-mode.sym')
local sym = require('storm-mode.sym').literal

---Decoded s-expressions:
--- - nil (tag 0x00)       → vim.NIL
--- - list (tag 0x01)      → Lua array; an improper tail is stored in the `tail`
---                          field, e.g. `(a . "b")` → `{ sym 'a', tail = 'b' }`
--- - number (tag 0x02)    → integer
--- - string (tag 0x03)    → string
--- - symbol (0x04, 0x05)  → storm-mode.sym
---@alias storm-mode.sexp storm-mode.sexp.list | integer | string | storm-mode.sym | vim.NIL

---@class storm-mode.sexp.list: { [integer]: storm-mode.sexp }
---@field tail? storm-mode.sexp improper tail of a dotted list

---@param s string
---@param p integer 1-based position
---@return integer value, integer next
local function dec_number(s, p)
    local a, b, c, d = s:byte(p, p + 3)
    if d == nil then error('truncated number', 0) end
    return ((a * 0x100 + b) * 0x100 + c) * 0x100 + d, p + 4
end

---@return string value, integer next
local function dec_string(s, p)
    local len
    len, p = dec_number(s, p)
    if p + len - 1 > #s then error('truncated string', 0) end
    return s:sub(p, p + len - 1), p + len
end

local dec_entry

---Decode a list starting after its first 0x01 tag. Lists are decoded
---iteratively; only nesting recurses.
local function dec_list(s, p)
    local list = {}
    local value
    value, p = dec_entry(s, p)
    list[1] = value
    while s:byte(p) == 0x01 do
        value, p = dec_entry(s, p + 1)
        list[#list + 1] = value
    end
    local tail
    tail, p = dec_entry(s, p)
    if tail ~= vim.NIL then list.tail = tail end
    return list, p
end

---@param s string
---@param p integer
---@return storm-mode.sexp value, integer next
function dec_entry(s, p)
    local tag = s:byte(p)
    p = p + 1
    if tag == 0x00 then
        return vim.NIL, p
    elseif tag == 0x01 then
        return dec_list(s, p)
    elseif tag == 0x02 then
        return dec_number(s, p)
    elseif tag == 0x03 then
        return dec_string(s, p)
    elseif tag == 0x04 then
        local id, name
        id, p = dec_number(s, p)
        name, p = dec_string(s, p)
        local new_sym = sym(name)
        Sym.sym_to_symid[name] = id
        Sym.symid_to_sym[id] = new_sym
        return new_sym, p
    elseif tag == 0x05 then
        local id
        id, p = dec_number(s, p)
        local known = Sym.symid_to_sym[id]
        if known == nil then error('unknown symbol id ' .. id, 0) end
        return known, p
    elseif tag == nil then
        error('truncated message', 0)
    end
    error(string.format('invalid tag 0x%02x', tag), 0)
end

---Decode the first message in `buffer`.
---
---Returns one of:
--- - `string, rest`: text output from Storm (everything up to the next null byte)
--- - `message, rest`: a decoded message (a list)
--- - `nil, buffer`: the buffer is empty or the message is not complete yet
--- - `nil, rest, err`: the message was complete but could not be decoded; it
---   has been skipped so that later messages can still be read
---@param buffer string
---@return string | storm-mode.sexp.list | nil payload
---@return string rest
---@return string? err
function M.dec_message(buffer)
    if #buffer == 0 then return nil, '' end

    if buffer:byte(1) ~= 0x00 then
        local stop = buffer:find('\0', 1, true)
        if stop then return buffer:sub(1, stop - 1), buffer:sub(stop) end
        return buffer, ''
    end

    if #buffer < 5 then return nil, buffer end
    local len = dec_number(buffer, 2)
    local body_end = 5 + len
    if #buffer < body_end then return nil, buffer end

    local body = buffer:sub(6, body_end)
    local rest = buffer:sub(body_end + 1)
    local ok, value, next_p = pcall(dec_entry, body, 1)
    if not ok then return nil, rest, 'failed to decode message: ' .. tostring(value) end
    if next_p ~= #body + 1 then return nil, rest, string.format('message has %d trailing bytes', #body + 1 - next_p) end
    if type(value) ~= 'table' or Sym.is_sym(value) then return nil, rest, 'message is not a list' end
    return value, rest
end

return M
