local M = {}

local Lsp = require('storm-mode.lsp')
local Sym = require('storm-mode.sym')
local Util = require('storm-mode.util')
local sym = require('storm-mode.sym').literal

---@type table<integer, integer>
M.sbuf_to_buf = {}
---@type table<integer, integer>
M.buf_to_sbuf = {}
local next_sbufnr = 1
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
    vim.api.nvim_set_option_value('filetype', 'storm', { buf = bufnr })

    local file_name = vim.api.nvim_buf_get_name(bufnr)
    local bufstr = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    local cursor_position = 0
    local sbufnr = next_sbufnr
    M.buf_to_sbuf[bufnr] = sbufnr
    M.sbuf_to_buf[sbufnr] = bufnr
    next_sbufnr = next_sbufnr + 1

    local message = { sym 'open', sbufnr, file_name, bufstr, cursor_position }
    Lsp.send(message)
end

---Unset storm-mode for bufnr or current buffer
---@param bufnr? integer
function M.unset_mode(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.api.nvim_set_option_value('filetype', '', { buf = bufnr })

    local sbufnr = M.buf_to_sbuf[bufnr]
    M.buf_to_sbuf[bufnr] = nil
    M.sbuf_to_buf[sbufnr] = nil

    local message = { sym 'close', sbufnr }
    Lsp.send(message)
end

function M.quit()
    for k, _ in pairs(M.buf_to_sbuf) do
        M.unset_mode(k)
    end

    local message = { sym 'quit' }
    Lsp.send(message)

    Lsp.process_buffer = ''
    Sym.sym_to_symid = {}
end

---Request color information again
function M.recolor()
    local bufnr = vim.api.nvim_get_current_buf()
    local sbufnr = M.buf_to_sbuf[bufnr]

    local message = { sym 'color', sbufnr }
    Lsp.send(message)
end

---Color the buffer bufnr with colors
---@param sbufnr integer
---@param colors [integer, storm-mode.sym][]
---@param _ integer edit number
---@param start_ch integer start character
function M.color_buffer(sbufnr, colors, _, start_ch)
    if start_ch ~= 0 then
        vim.notify('need to calculate line and col pos for start character!')
        return
    end

    local bufnr = M.sbuf_to_buf[sbufnr]
    local bufstr = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    local line, col = 0, 0
    local end_row, end_col
    local byte = 1
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    for _, span_highlight in ipairs(colors) do
        end_row, end_col, byte = Util.charadv_bytepos(bufstr, line, col, byte, span_highlight[1])
        if span_highlight[2] ~= sym 'nil' then
            local hl_group = color_maps[tostring(span_highlight[2])]
            vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, col, {
                hl_group = hl_group,
                end_row = end_row,
                end_col = end_col,
                right_gravity = false,    -- Extend extmark on text left
                end_right_gravity = true, -- Extend extmark on text right
            })
        end
        line = end_row
        col = end_col
    end
end

return M
