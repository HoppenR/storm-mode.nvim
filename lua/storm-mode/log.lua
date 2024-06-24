local M = {}

---@param message string
function M.print(message)
    local lines = vim.split(message, '\n', { plain = true })
    vim.api.nvim_buf_set_lines(M._bufnr, -2, -1, false, lines)
end

---Open the log buffer
function M.show()
    vim.api.nvim_open_win(M._bufnr, true, { split = 'right' })
end

function M.clear()
    vim.api.nvim_buf_set_lines(M._bufnr, 0, -1, false, { '--- Empty ---' })
end

---Get the log lines
---@return string[]
function M.get()
    return vim.api.nvim_buf_get_lines(M._bufnr, 0, -1, false)
end

M._bufnr = vim.api.nvim_create_buf(false, true)
M.clear()

return M
