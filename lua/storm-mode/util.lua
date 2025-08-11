local M = {}

---@param bufnr integer
---@param start_row integer
---@param start_col integer
---@param delta_row integer offset from start row
---@param end_col integer if end row = 0, offset from start row
---@return string, boolean (newstr, full_line)
function M.get_buf_newstr(bufnr, start_row, start_col, delta_row, end_col)
    if delta_row == 0 then
        end_col = end_col + start_col
    end
    local end_row = start_row + delta_row
    if start_col == 0 and end_col == 0 then
        local new_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, true)
        return table.concat(new_lines, '\n'), true
    else
        local new_text = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
        return table.concat(new_text, '\n'), false
    end
end

---Get char pos at the start of line in an array
---@param data string[]
---@param line integer
---@return integer
function M.charpos(data, line)
    local charpos = 0
    local i = 1
    while i <= line do
        charpos = charpos + vim.fn.strchars(data[i]) + 1
        i = i + 1
    end
    return charpos
end

---Get char pos for byte pos in bufnr (should always be current buffer)
---@param bufnr integer
---@param mbytes table<integer, integer>
---@param byte integer
---@return integer
function M.byte2char(bufnr, mbytes, byte)
    assert(vim.api.nvim_get_current_buf() == bufnr, 'byte2char in buffer other than current')
    local res = byte
    for pos, sz in pairs(mbytes) do
        if byte > pos then
            res = res - sz + 1
        end
    end
    return res
end

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

        if c == 0x0A then
            line = line + 1
            line_byte = 0
        else
            if c >= 0xF0 then
                char_len = 4
            elseif c >= 0xE0 then
                char_len = 3
            elseif c >= 0xC0 then
                char_len = 2
            end
            line_byte = line_byte + char_len
        end

        byte = byte + char_len
        adv_amt = adv_amt - 1
    end
    return line, line_byte, byte
end

return M
