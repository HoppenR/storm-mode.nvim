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

-- TODO: This should store the difference in bytes AND characters?
--       bytes to be able to adjust the ext_mark positionings to a previous changedtick?
--       characters to be able to adjust the incoming colors?
--       ... needs more condsideration
--- @class storm-mode.buffer.edit
--- @field edit-began integer
--- @field old-len integer
--- @field new-len string

local augroup = vim.api.nvim_create_augroup('StormMode', { clear = true })
local ns_id = vim.api.nvim_create_namespace('storm-mode')
---@type table<integer, integer[]>
M.buf_autocmd_handlers = {}
---@type table<string, boolean>
M.supported_ft = {}
---@type table<integer, integer>
local sbuf_to_buf = {}
---@type table<integer, integer>
local buf_to_sbuf = {}
-- ---@type table<integer, table<integer, storm-mode.buffer.edit>> sbuf -> changedtick -> edit
-- local bufedits = {}
-- ---@type table<integer, integer> sbuf -> changedtick
-- local sbufchangedtick = {}
---@type integer
local next_sbufnr = 1
---@type table<integer, table<integer, integer>> sbuf -> multibyte position -> size
local sbuf_mbytes = {}

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
        if vim.api.nvim_buf_is_loaded(bufnr) then
            M.set_mode_if_supported(bufnr)
        end
    end
end

---Set storm-mode for current buffer if the extension is supported according to
---the compiler, does not attempt to start the compiler if it is not running
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

    M.buf_autocmd_handlers[bufnr] = M.buf_autocmd_handlers[bufnr] or {}
    -- table.insert(M.buf_autocmd_handlers[bufnr],
    --     vim.api.nvim_create_autocmd({ 'TextYankPost', 'TextChanged', 'TextChangedI' }, {
    --         buffer = bufnr,
    --         group = augroup,
    --         callback = M.on_change,
    --     })
    -- )
    vim.api.nvim_buf_attach(bufnr, false, {
        on_bytes = M.on_change,
        utf_sizes = true,
    })
    table.insert(M.buf_autocmd_handlers[bufnr],
        vim.api.nvim_create_autocmd('CursorMoved', {
            buffer = bufnr,
            group = augroup,
            callback = M.auto_update_cursor,
        })
    )

    local buflines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    -- local changedtick = 0 -- vim.api.nvim_buf_get_changedtick(bufnr)
    -- bufedits[bufnr] = {}
    -- bufedits[bufnr][changedtick] = buflines
    -- sbufchangedtick[bufnr] = changedtick

    ---@type string
    local bufstr = table.concat(buflines, '\n')
    local last = 0
    ---@type table<integer, integer>
    local mbytes = {}
    for _, utf_pos in ipairs(vim.str_utf_pos(bufstr)) do
        if utf_pos > last + 1 then
            mbytes[last] = utf_pos - last
        end
        last = utf_pos
    end
    -- TODO: Edge case when a file ENDS with a multibyte as a last character

    local file_name = vim.api.nvim_buf_get_name(bufnr)
    local cursor_position = 0 -- TODO: is it?
    local sbufnr = next_sbufnr
    buf_to_sbuf[bufnr] = sbufnr
    sbuf_to_buf[sbufnr] = bufnr
    sbuf_mbytes[sbufnr] = mbytes
    next_sbufnr = next_sbufnr + 1

    Lsp.send({ sym 'open', sbufnr, file_name, bufstr, cursor_position })
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

    for _, handle_id in ipairs(M.buf_autocmd_handlers[bufnr]) do
        vim.api.nvim_del_autocmd(handle_id)
    end

    buf_to_sbuf[bufnr] = nil
    sbuf_to_buf[sbufnr] = nil
    M.buf_autocmd_handlers[bufnr] = nil

    Lsp.send({ sym 'close', sbufnr })
end

--- @type fun(type: "bytes", bufnr: integer, changedtick: integer, start_row: integer, start_col: integer, start_byte: integer, old_end_row: integer, old_end_col: integer, old_end_byte: integer, new_end_row: integer, new_end_col: integer, new_end_byte: integer): boolean?
function M.on_change(type, bufnr, changedtick,
                     start_row, start_col, start_byte,
                     old_end_row, old_end_col, old_end_byte,
                     new_end_row, new_end_col, new_end_byte)
    assert(type == 'bytes', 'on_change should only handle bytes events')
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then
        return
    end

    -- TODO: Bufedit unwinding to adjust ext-marks
    -- TODO: limit edit length

    ---@type table<integer, integer>
    local mbytes = sbuf_mbytes[sbufnr]
    local start_char = Util.byte2char(bufnr, mbytes, start_byte)
    local old_end_char = Util.byte2char(bufnr, mbytes, start_byte + old_end_byte) - start_char

    -- Update mbytes deletions
    for i = start_byte + old_end_byte, start_byte, -1 do
        mbytes[i] = nil
    end

    -- Get newly inserted string
    ---@type string, boolean
    local newstr, end_of_buffer = Util.get_buf_newstr(bufnr, start_row, start_col, new_end_row, new_end_col)

    -- Add new multibyte info
    local last = 0
    for _, new_utf_pos in ipairs(vim.str_utf_pos(newstr)) do
        if new_utf_pos > last + 1 then
            mbytes[last + start_byte] = new_utf_pos - last
        end
        last = new_utf_pos
    end

    -- Shift multibytes after new string
    ---@type table<integer, integer>
    local shifted_mbytes = {}
    local diff = new_end_byte - old_end_byte
    local shift_start = start_byte + 1 + old_end_byte
    for pos, sz in pairs(mbytes) do
        if pos < shift_start then
            shifted_mbytes[pos] = sz
        else
            shifted_mbytes[pos + diff] = sz
        end
    end
    sbuf_mbytes[sbufnr] = shifted_mbytes

    -- table.insert(bufedits, {
    --     ['edit-began'] = start_byte,
    --     ['old-len'] = old_end_byte,
    --     ['new-len'] = new_end_byte,
    -- })

    if end_of_buffer then
        start_char = start_char - 1
        newstr = '\n' .. newstr
    end
    Lsp.send({ sym 'edit', sbufnr, changedtick, start_char, start_char + old_end_char, newstr })
end

function M.quit()
    for bufnr, _ in pairs(buf_to_sbuf) do
        M.unset_mode(bufnr)
    end
    Lsp.send({ sym 'quit' })
    Sym.sym_to_symid = {}
end

---@param opts vim.AutocmdOpts
function M.auto_update_cursor(opts)
    local sbufnr = buf_to_sbuf[opts.buf]
    -- local lastbuftick = sbufchangedtick[opts.buf]
    -- local bufstate = bufedits[opts.buf][lastbuftick]
    local cursor = vim.api.nvim_win_get_cursor(0)
    if true then
        return -- FIXME
    end
    -- local cursor_char_pos = Util.charpos(bufstate, cursor[1] + 1)
    Lsp.send({ sym 'point', sbufnr, cursor[1] + 1 })
end

function M.debug_error()
    local bufnr = vim.api.nvim_get_current_buf()
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then return end
    Lsp.send({ sym 'error', sbufnr })
end

---Request color information again
function M.debug_recolor()
    local bufnr = vim.api.nvim_get_current_buf()
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then return end
    Lsp.send({ sym 'color', sbufnr })
end

function M.debug_tree()
    local bufnr = vim.api.nvim_get_current_buf()
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then return end
    Lsp.send({ sym 'debug', sbufnr, vim.NIL })
end

function M.debug_content()
    local bufnr = vim.api.nvim_get_current_buf()
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then return end
    Lsp.send({ sym 'debug', sbufnr, sym 't' })
end

---Color the buffer bufnr with colors
---@param sbufnr integer
---@param colors [integer, storm-mode.sym][]
---@param changedtick integer edit number
---@param start_ch integer start character
function M.apply_colors(sbufnr, colors, changedtick, start_ch)
    if start_ch ~= 0 then
        table.insert(colors, 0, { start_ch, vim.NIL })
    end

    local bufnr = sbuf_to_buf[sbufnr]
    if bufnr == nil then
        -- Buffer was be closed
        return
    end

    -- TODO: use current buffer text, but adjust extmarks based on bufedits[bufnr][changedtick]
    local bufstr = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    -- TODO: Check if the last HANDLED changedtick is ACTUALLY the last changedtick
    --       else we cannot reliably draw??
    -- local edits = bufedits[bufnr][changedtick]
    local line, col = 0, 0
    local end_row, end_col
    local byte = 1
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    for _, span_highlight in pairs(colors) do
        end_row, end_col, byte = Util.charadv_bytepos(bufstr, line, col, byte, span_highlight[1])
        if span_highlight[2] ~= vim.NIL then
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
