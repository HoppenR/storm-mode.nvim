local M = {}

local sym = require('storm-mode.sym').literal

M.buffers = {} ---@type table<integer, integer>
M.next_id = 1 ---@type integer

---Set new buffer into storm_mode
function M.storm_mode()
    vim.api.nvim_set_option_value('tabstop', 4, { buf = 0 })
    vim.api.nvim_set_option_value('shiftwidth', 4, { buf = 0 })
    vim.api.nvim_set_option_value('softtabstop', 4, { buf = 0 })
    vim.api.nvim_set_option_value('expandtab', true, { buf = 0 })
    vim.api.nvim_set_option_value('filetype', 'storm', { buf = 0 })
    M.register_buffer(vim.api.nvim_get_current_buf())
end

---Tell the LSP about a new buffer
---@param bufnr integer
function M.register_buffer(bufnr)
    if not vim.b[bufnr].storm_buffer_id then
        vim.api.nvim_buf_set_var(bufnr, 'storm_buffer_id', M.next_id)
        M.buffers[M.next_id] = bufnr
        M.next_id = M.next_id + 1
    end

    vim.api.nvim_buf_set_var(bufnr, 'storm_buffer_edit_id', 0)
    vim.api.nvim_buf_set_var(bufnr, 'storm_buffer_edits', {})
    vim.api.nvim_buf_set_var(bufnr, 'storm_buffer_last_point', 0)
    local buffer_id = vim.b[bufnr].storm_buffer_id

    local file_name = vim.api.nvim_buf_get_name(bufnr)
    local buffer_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    local cursor_position = 0

    local message = { sym 'open', buffer_id, file_name, buffer_content, cursor_position }
    require('storm-mode.lsp').send(message)
end

return M
