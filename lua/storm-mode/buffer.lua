local M = {}

local sym = require('storm-mode.sym').literal
local Util = require('storm-mode.util')

---@type table<integer, integer>
M.buffers = {}
M.next_id = 1

local ns_id = vim.api.nvim_create_namespace('storm-mode')

local color_maps = {
    ['comment'] = 'Comment',
    ['delimiter'] = 'Delimiter',
    ['string'] = 'String',
    ['constant'] = 'Constant',
    ['keyword'] = 'Keyword',
    ['fn-name'] = 'Function',
    ['var-name'] = 'Identifier',
    ['type-name'] = 'Type',
}

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

---Color the buffer bufnr with colors
---@param storm_bufnr integer
---@param colors [integer, storm-mode.sym][]
---@param _ integer edit number
---@param start_ch integer start character
function M.color_buffer(storm_bufnr, colors, _, start_ch)
    if start_ch ~= 0 then
        vim.notify('need to calculate line and col pos for start character!')
        return
    end

    local bufnr = M.buffers[storm_bufnr]
    local bufstr = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    local line, col = 0, 0
    local end_row, end_col
    local byte = 1
    for _, v in ipairs(colors) do
        end_row, end_col, byte = Util.charadv_bytepos(bufstr, line, col, byte, v[1])
        local hl_group = color_maps[tostring(v[2])]
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, col, {
            hl_group = hl_group,
            end_row = end_row,
            end_col = end_col,
            -- right_gravity = false,    -- Extend extmark on text left
            -- end_right_gravity = true, -- Extend extmark on text right
        })
        line = end_row
        col = end_col
    end
end

return M
