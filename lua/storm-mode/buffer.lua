local M = {}

local Config = require('storm-mode.config')
local Handlers = require('storm-mode.handlers')
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
---@type table<string, boolean>
M.supported_ft = {}

---@type table<integer, integer>
local sbuf_to_buf = {}
---@type table<integer, integer>
local buf_to_sbuf = {}
---@type table<integer, table<integer, string[]>>
local bufstates = {}
---@type table<integer, integer>
local lastbufchangedtick = {}
local next_sbufnr = 1

function M.setup()
    vim.api.nvim_create_user_command('StormDebugReColor', M.recolor, {})
    vim.api.nvim_create_user_command('StormQuit', M.quit, {})
    vim.api.nvim_create_user_command('StormStart', M.manual_set_mode, {})
    vim.api.nvim_create_user_command('StormClose', M.manual_unset_mode, {})
    vim.api.nvim_create_user_command('GlobalStormMode', M.global_set_mode, {})
end

function M.global_set_mode()
    vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
        group = augroup,
        callback = M.auto_set_mode,
    })
    vim.api.nvim_create_autocmd('BufUnload', {
        group = augroup,
        callback = M.auto_unset_mode,
    })
    Lsp.start()

    local buffers = vim.api.nvim_list_bufs()
    for _, bufnr in ipairs(buffers) do
        M.set_mode_if_supported(bufnr)
    end
end

---Set storm-mode for current buffer if the extension is supported according to
---the compiler. Does not attempt to start the compiler if it is not running.
---@param bufnr integer
function M.set_mode_if_supported(bufnr)
    if buf_to_sbuf[bufnr] ~= nil then
        return
    end

    local bufft = vim.fn.expand('#' .. bufnr .. ':e')
    if bufft == '' then
        return
    end

    local supported = M.supported_ft[bufft]
    if supported ~= nil then
        if supported then
            M.set_mode(bufnr)
        end
        return
    end

    if not Lsp.is_running() then
        return
    end

    Handlers.waiting_jobs[bufft] = Handlers.waiting_jobs[bufft] or {}
    table.insert(Handlers.waiting_jobs[bufft], function(result)
        M.supported_ft[bufft] = result
        if result then
            M.set_mode(bufnr)
        end
    end)

    Lsp.send({ sym 'supported', bufft })
end

--- @param opts vim.AutocmdOpts
function M.auto_set_mode(opts)
    M.set_mode_if_supported(opts.buf)
end

function M.manual_set_mode()
    local bufnr = vim.api.nvim_get_current_buf()
    M.set_mode(bufnr)
end

---Set mode for buf or current buffer
---@param bufnr integer
function M.set_mode(bufnr)
    vim.api.nvim_set_option_value('filetype', 'storm', { buf = bufnr })

    vim.api.nvim_create_autocmd({ 'TextYankPost', 'TextChanged', 'TextChangedI' }, {
        buffer = bufnr,
        group = augroup,
        callback = M.on_change,
    })

    local buflines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    -- First edit is always considered 0
    local changedtick = 0 -- vim.api.nvim_buf_get_changedtick(bufnr)
    bufstates[bufnr] = {}
    bufstates[bufnr][changedtick] = buflines
    lastbufchangedtick[bufnr] = changedtick

    local file_name = vim.api.nvim_buf_get_name(bufnr)
    local cursor_position = 0
    local sbufnr = next_sbufnr
    buf_to_sbuf[bufnr] = sbufnr
    sbuf_to_buf[sbufnr] = bufnr
    next_sbufnr = next_sbufnr + 1

    Lsp.send({ sym 'open', sbufnr, file_name, table.concat(buflines, '\n'), cursor_position })
end

--- @param opts vim.AutocmdOpts
function M.auto_unset_mode(opts)
    M.unset_mode(opts.buf)
end

function M.manual_unset_mode()
    local bufnr = vim.api.nvim_get_current_buf()
    M.unset_mode(bufnr)
end

---@param bufnr integer
function M.unset_mode(bufnr)
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then
        return
    end

    buf_to_sbuf[bufnr] = nil
    sbuf_to_buf[sbufnr] = nil

    Lsp.send({ sym 'close', sbufnr })
end

---Called on any buffer change, except 'TextYankPost' into the null register
---@param opts vim.AutocmdOpts
function M.on_change(opts)
    if vim.v.event.operator == 'y' then
        return
    end

    local bufstate = vim.api.nvim_buf_get_lines(opts.buf, 0, -1, false)
    local changedtick = vim.api.nvim_buf_get_changedtick(opts.buf)
    local lastbuftick = lastbufchangedtick[opts.buf]
    local lastbufstate = bufstates[opts.buf][lastbuftick]

    local bufstr = table.concat(bufstate, '\n')
    local lastbufstr = table.concat(lastbufstate, '\n')

    local diffops = { result_type = 'indices', algorithm = 'minimal' }
    ---@cast diffops vim.diff.Opts silence warning about missing fields
    local diffs = vim.diff(lastbufstr, bufstr, diffops)
    assert(type(diffs) == 'table')

    local sbufnr = buf_to_sbuf[opts.buf]

    for _, diff in ipairs(diffs) do
        if diff[2] == 0 then diff[1] = diff[1] + 1 end
        local laststartline = diff[1] + 1
        local lastendline = laststartline + diff[2]

        if diff[4] == 0 then diff[3] = diff[3] + 1 end
        local startline = diff[3] + 1
        local endline = startline + diff[4]

        -- TODO: This assumes one diff happens at once, `:%s/a/` is a bug
        local laststartchar = Util.charpos(lastbufstate, laststartline)
        local lastendchar = Util.charpos(lastbufstate, lastendline)
        local startchar = Util.charpos(bufstate, startline)
        local endchar = Util.charpos(bufstate, endline)

        local newstr = vim.fn.strcharpart(bufstr, startchar, endchar - startchar)

        Lsp.send({ sym 'edit', sbufnr, changedtick, laststartchar, lastendchar, newstr })
    end

    bufstates[opts.buf][changedtick] = bufstate
    lastbufchangedtick[opts.buf] = changedtick
end

function M.quit()
    for bufnr, _ in pairs(buf_to_sbuf) do
        M.unset_mode(bufnr)
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
    for _, span_highlight in pairs(colors) do
        end_row, end_col, byte = Util.charadv_bytepos(bufstr, line, col, byte, span_highlight[1])
        if span_highlight[2] ~= sym 'nil' then
            local hl_name = tostring(span_highlight[2])
            local hl_group = Config.highlights[hl_name]
            local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line, col }, { end_row, end_col }, {})
            for _, extmark in ipairs(extmarks) do
                vim.api.nvim_buf_del_extmark(bufnr, ns_id, extmark[1])
            end
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
