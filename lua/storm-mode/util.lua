local M = {}

---Iterate adv_amt characters in data and return the new (line, line_byte, byte)
---assuming byte b is at (line, line_byte)
---@param data string the data to iterate over
---@param line integer the line to start at
---@param line_byte integer the byte offset into the line
---@param byte integer the starting byte position in data
---@param adv_amt integer amount of multibyte characters to advance
---@return integer
---@return integer
---@return integer
function M.charadv_bytepos(data, line, line_byte, byte, adv_amt)
    while adv_amt > 0 do
        local c = data:byte(byte)
        local char_len = 1

        if c >= 0xF0 then
            char_len = 4
        elseif c >= 0xE0 then
            char_len = 3
        elseif c >= 0xC0 then
            char_len = 2
        end

        if c == 0x0A then
            line = line + 1
            line_byte = 0
        else
            line_byte = line_byte + char_len
        end

        byte = byte + char_len
        adv_amt = adv_amt - 1
    end
    return line, line_byte, byte
end

return M
