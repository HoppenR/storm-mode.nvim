local M = {}

local Lsp = require('storm-mode.lsp')
local Sym = require('storm-mode.sym')
local Util = require('storm-mode.util')
local sym = require('storm-mode.sym').literal

--- @class vim.AutocmdOpts
--- @field id number
--- @field event string
--- @field group? number
--- @field match string
--- @field buf number
--- @field file string
--- @field data any

local augroup = vim.api.nvim_create_augroup('StormMode', { clear = true })
local ns_id = vim.api.nvim_create_namespace('storm-mode')

---@type table<integer, integer>
local sbuf_to_buf = {}
---@type table<integer, integer>
local buf_to_sbuf = {}
---@type table<integer, table<integer, string[]>>
local bufstates = {}
---@type table<integer, integer>
local lastbufchangedtick = {}
local next_sbufnr = 1

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

function M.setup()
    vim.api.nvim_create_autocmd('BufRead', {
        pattern = '*.bs',
        group = augroup,
        callback = M.set_mode,
    })
    vim.api.nvim_create_autocmd('BufUnload', {
        pattern = '*.bs',
        group = augroup,
        callback = M.unset_mode,
    })
    vim.api.nvim_create_autocmd({ 'TextYankPost', 'TextChanged', 'TextChangedI' }, {
        pattern = '*.bs',
        group = augroup,
        callback = M.on_change,
    })
end

---Set new buffer into storm-mode
---@param args vim.AutocmdOpts
function M.set_mode(args)
    vim.api.nvim_set_option_value('filetype', 'storm', { buf = args.buf })

    local buflines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
    -- First edit is always considered 0
    local changedtick = 0 -- vim.api.nvim_buf_get_changedtick(bufnr)
    bufstates[args.buf] = {}
    bufstates[args.buf][changedtick] = buflines
    lastbufchangedtick[args.buf] = changedtick

    vim.api.nvim_buf_create_user_command(args.buf, 'StormQuit', M.quit, {})
    vim.api.nvim_buf_create_user_command(args.buf, 'StormDebugReColor', M.recolor, {})

    local file_name = vim.api.nvim_buf_get_name(args.buf)
    local cursor_position = 0
    local sbufnr = next_sbufnr
    buf_to_sbuf[args.buf] = sbufnr
    sbuf_to_buf[sbufnr] = args.buf
    next_sbufnr = next_sbufnr + 1

    Lsp.send({ sym 'open', sbufnr, file_name, table.concat(buflines, '\n'), cursor_position })
end

---Unset storm-mode for bufnr or current buffer
---@param args vim.AutocmdOpts
function M.unset_mode(args)
    -- TODO: Remove buffer local user commands (struct?)
    local sbufnr = buf_to_sbuf[args.buf]
    buf_to_sbuf[args.buf] = nil
    sbuf_to_buf[sbufnr] = nil

    Lsp.send({ sym 'close', sbufnr })
end

---Called on any buffer change, except 'TextYankPost' into the null register
---@param args vim.AutocmdOpts
function M.on_change(args)
    if vim.v.event.operator == 'y' then
        return
    end

    local bufstate = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
    local changedtick = vim.api.nvim_buf_get_changedtick(args.buf)
    local lastbuftick = lastbufchangedtick[args.buf]
    local lastbufstate = bufstates[args.buf][lastbuftick]

    local bufstr = table.concat(bufstate, '\n')
    local lastbufstr = table.concat(lastbufstate, '\n')

    local diffops = { result_type = 'indices', algorithm = 'minimal' }
    ---@cast diffops vim.diff.Opts silence warning about missing fields
    local diffs = vim.diff(lastbufstr, bufstr, diffops)
    assert(type(diffs) == 'table')

    local sbufnr = buf_to_sbuf[args.buf]

    for _, diff in ipairs(diffs) do
        if diff[2] == 0 then diff[1] = diff[1] + 1 end
        local laststartline = diff[1] + 1
        local lastendline = laststartline + diff[2]

        if diff[4] == 0 then diff[3] = diff[3] + 1 end
        local startline = diff[3] + 1
        local endline = startline + diff[4]

        local laststartchar = Util.charpos(lastbufstate, laststartline)
        local lastendchar = Util.charpos(lastbufstate, lastendline)
        local startchar = Util.charpos(bufstate, startline)
        local endchar = Util.charpos(bufstate, endline)

        local newstr = vim.fn.strcharpart(bufstr, startchar, endchar - startchar)

        Lsp.send({ sym 'edit', sbufnr, changedtick, laststartchar, lastendchar, newstr })
    end

    bufstates[args.buf][changedtick] = bufstate
    lastbufchangedtick[args.buf] = changedtick
end

function M.quit()
    for bufid, _ in pairs(buf_to_sbuf) do
        -- Trigger bufunload autocommands
        vim.api.nvim_buf_delete(bufid, { unload = true })
    end

    Lsp.send({ sym 'quit' })

    Sym.sym_to_symid = {}
end

---Request color information again
function M.recolor()
    local bufnr = vim.api.nvim_get_current_buf()
    local sbufnr = buf_to_sbuf[bufnr]

    Lsp.send({ sym 'color', sbufnr })
end

---Color the buffer bufnr with colors
---@param sbufnr integer
---@param colors [integer, storm-mode.sym][]
---@param changedtick integer edit number
---@param start_ch integer start character
function M.apply_colors(sbufnr, colors, changedtick, start_ch)
    if start_ch ~= 0 then
        table.insert(colors, 0, { start_ch, sym 'nil' })
    end

    local bufnr = sbuf_to_buf[sbufnr]
    local lastchangedtick = lastbufchangedtick[bufnr]
    if changedtick ~= lastchangedtick then
        print(changedtick, lastchangedtick)
        vim.notify("Out of sync")
        return
    end

    local bufstr = table.concat(bufstates[bufnr][changedtick], '\n')
    local line, col = 0, 0
    local end_row, end_col
    local byte = 1
    -- TODO: Only clear the line as if drawing to it
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    for _, span_highlight in pairs(colors) do
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
