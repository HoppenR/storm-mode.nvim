local M = {}

local sym = require('storm-mode.sym').literal

M.buffers = {} ---@type table<integer, integer>
M.next_id = 1 ---@type integer

local ns = vim.api.nvim_create_namespace('storm-mode')

---Set new buffer into storm-mode
function M.set_mode()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_option_value('tabstop', 4, { buf = bufnr })
    vim.api.nvim_set_option_value('shiftwidth', 4, { buf = bufnr })
    vim.api.nvim_set_option_value('softtabstop', 4, { buf = bufnr })
    vim.api.nvim_set_option_value('expandtab', true, { buf = bufnr })
    vim.api.nvim_set_option_value('filetype', 'storm', { buf = bufnr })
    M.register_buffer(bufnr)
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

local color_translation = {
    ['comment'] = 'Comment',
    ['delimiter'] = 'Delimiter',
    ['string'] = 'String',
    ['constant'] = 'Constant',
    ['keyword'] = 'Keyword',
    ['fn-name'] = 'Function',
    ['var-name'] = 'Identifier',
    ['type-name'] = 'Type',
    ['nil'] = nil,
}

---Color the buffer bufnr with colors
---@param bufnr integer
---@param colors [integer, storm-mode.sym][]
function M.color_buffer(bufnr, colors)
    local i = 0
    for _, v in pairs(colors) do
        vim.api.nvim_buf_set_extmark(
            M.buffers[bufnr],
            ns,
            0,
            i,
            {
                hl_group = color_translation[tostring(v[2])],
                end_col = i + v[1],
            }
        )
        i = i + v[1]
    end
end

return M
