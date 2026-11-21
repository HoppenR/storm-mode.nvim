local M = {}

local Config = require('storm-mode.config')
local Lsp = require('storm-mode.lsp')
local Output = require('storm-mode.output')
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
---@type table<integer, integer[]>  -- bufnr → autocmd ids
M.buf_autocmd_handlers = {}
---@type table<string, boolean>
M.supported_ft = {}
---@type table<integer, integer>
local sbuf_to_buf = {}
---@type table<integer, integer>
local buf_to_sbuf = {}
---Current content using Neovim's byte model: every line, including the last,
---is terminated by '\n'. This matches the offsets reported by on_bytes.
---@type table<integer, string>
local bufcontents = {}
---@type table<integer, table<integer,string>>  -- bufnr → {[edit_id]=content after that edit}
local buf_snapshots = {}
---@type table<integer, {id:integer,byte_offset:integer,old_len:integer,new_len:integer}[]>
local edit_log = {}
---Last edit id sent to Storm per buffer. 0 is the `open` message. Ticks are not
---used because one undo fires several on_bytes callbacks with the same tick.
---@type table<integer, integer>
local last_edit_id = {}
---Changes recorded by on_bytes, not yet sent to Storm (see M.flush)
---@type table<integer, {old_start:integer,old_end:integer,new_start:integer,new_end:integer,text:string}[]>
local pending_hunks = {}
---Identifies the current nvim_buf_attach listener of a buffer. Detaching is
---lazy (the listener returns true on its next call), so a listener from an
---earlier set_mode can still be attached; it must ignore changes.
---@type table<integer, table>
local attach_token = {}
---Buffer options and mappings replaced by set_mode, restored by unset_mode
---@type table<integer, {indentexpr: string, indentkeys: string, omnifunc: string, mapped_k: boolean, tabstop?: integer, shiftwidth?: integer}>
local saved_settings = {}
---Last cursor position sent with `point`
---@type table<integer, integer>
local last_point = {}
local next_sbufnr = 1

---Milliseconds to wait for Storm to answer an indent request
local INDENT_TIMEOUT_MS = 500
---Milliseconds after the last change before checking a buffer for syntax errors
local CHECK_DELAY_MS = 500
---Counts scheduled syntax checks per buffer; only the latest one runs
---@type table<integer, integer>
local check_generation = {}

---Check a buffer for syntax errors (diagnostics) once changes have settled
---@param bufnr integer
local function schedule_check(bufnr)
    if not Config.diagnostics then return end
    local generation = (check_generation[bufnr] or 0) + 1
    check_generation[bufnr] = generation
    vim.defer_fn(function()
        -- Config is checked again: diagnostics may have been turned off meanwhile
        if check_generation[bufnr] == generation and buf_to_sbuf[bufnr] ~= nil and Config.diagnostics then
            require('storm-mode.errors').check(bufnr)
        end
    end, CHECK_DELAY_MS)
end
local MAX_SNAPSHOTS = 64

-- Transform a 0-based byte offset from the snapshot at edit_id forward to the
-- current buffer state by replaying every edit log entry with id > edit_id.
-- Returns nil if the offset falls inside a replaced range (a later edit deleted
-- those bytes; Storm will re-colour that region in its own response).
local function transform_byte_offset(log, edit_id, offset)
    for _, e in ipairs(log) do
        -- Edits that end before the offset shift it; edits after it don't matter
        if e.id > edit_id and offset >= e.byte_offset then
            if offset < e.byte_offset + e.old_len then
                return nil -- inside replaced range
            end
            offset = offset + e.new_len - e.old_len
        end
    end
    return offset
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
local function charadv_bytepos(data, line, line_byte, byte, adv_amt)
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

-- Advance a (row, col, byte_1based) cursor through content until
-- byte_1based == target_1based, tracking newlines.
-- Use for monotonically increasing targets; reset to (0,0,1) if going backward.
local function advance_to_byte(content, row, col, byte_1based, target_1based)
    while byte_1based < target_1based do
        if content:byte(byte_1based) == 0x0A then
            row = row + 1
            col = 0
        else
            col = col + 1
        end
        byte_1based = byte_1based + 1
    end
    return row, col, byte_1based
end

---Read the whole buffer in Neovim's byte model (trailing '\n' on every line)
---@param bufnr integer
---@return string
local function read_buffer(bufnr) return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n' end

---@param bufnr integer
---@param mode string
---@param lhs string
---@return boolean
local function has_buf_or_global_keymap(bufnr, mode, lhs)
    local normalized = vim.keymap.set and vim.keycode(lhs) or lhs

    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
        if map.lhs == lhs or map.lhs == normalized then return true end
    end

    for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
        if map.lhs == lhs or map.lhs == normalized then return true end
    end

    return false
end

---nvim_buf_get_text that accepts the end-of-buffer position (line_count, 0)
---which on_bytes uses for ranges that include the last line's newline.
---@return string
local function get_text(bufnr, start_row, start_col, end_row, end_col)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if start_row >= line_count then
        return '' -- nothing exists past the final newline
    end
    local trailing = ''
    if end_row >= line_count then
        end_row = line_count - 1
        end_col = #vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)[1]
        trailing = '\n'
    end
    local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
    return table.concat(lines, '\n') .. trailing
end

---Whether global storm-mode is on (see M.global_set_mode)
M.global_enabled = false
local global_augroup = vim.api.nvim_create_augroup('StormModeGlobal', { clear = true })

---Use storm-mode for every buffer whose extension Storm supports, now and later
---@param action? 'enable'|'disable'|'toggle' default 'enable'
function M.global_set_mode(action)
    action = action or 'enable'
    local enable = action == 'enable' or (action == 'toggle' and not M.global_enabled)
    M.global_enabled = enable
    vim.api.nvim_clear_autocmds({ group = global_augroup })
    if action == 'toggle' then Output.notify('global storm-mode is ' .. (enable and 'on' or 'off')) end
    if not enable then return end

    vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
        group = global_augroup,
        callback = M.auto_set_mode,
    })
    -- BufUnload is handled by on_detach inside nvim_buf_attach
    Lsp.start()

    local buffers = vim.api.nvim_list_bufs()
    for _, bufnr in ipairs(buffers) do
        if vim.api.nvim_buf_is_loaded(bufnr) then M.set_mode_if_supported(bufnr) end
    end
end

---Set storm-mode for current buffer if the extension is supported according to
---the compiler, does not attempt to start the compiler if it is not running
---@param bufnr integer
function M.set_mode_if_supported(bufnr)
    if buf_to_sbuf[bufnr] ~= nil then return end

    local bufft = vim.fn.expand('#' .. bufnr .. ':e')
    if bufft == '' then return end

    local supported = M.supported_ft[bufft]
    if supported ~= nil then
        if supported then M.set_mode(bufnr) end
        return
    end

    if not Lsp.is_running() then return end

    Lsp.request({ sym 'supported', bufft }, function(reply)
        if reply == nil then return end -- Storm exited
        M.supported_ft[bufft] = reply[2] == sym 't'
        if vim.api.nvim_buf_is_loaded(bufnr) then M.set_mode_if_supported(bufnr) end
    end)
end

--- @param opts vim.AutocmdOpts
function M.auto_set_mode(opts) M.set_mode_if_supported(opts.buf) end

function M.manual_set_mode()
    local bufnr = vim.api.nvim_get_current_buf()
    M.set_mode(bufnr)
end

---Character offset (as used by Storm) of a position, in the cached content
---@param bufnr integer
---@param row integer 0-based
---@param col integer 0-based byte column
---@return integer
local function char_at(bufnr, row, col)
    local content = bufcontents[bufnr]
    local byte = vim.api.nvim_buf_get_offset(bufnr, row) + col
    return vim.str_utfindex(content, 'utf-32', math.min(byte, #content), false)
end

---Character offset of the cursor in a window showing the buffer (the current
---window if it does), or 0
---@param bufnr integer
---@return integer
function M.cursor_char(bufnr)
    local win = vim.api.nvim_get_current_buf() == bufnr and 0 or vim.fn.bufwinid(bufnr)
    if bufcontents[bufnr] == nil or win == -1 then return 0 end
    local cursor = vim.api.nvim_win_get_cursor(win)
    return char_at(bufnr, cursor[1] - 1, cursor[2])
end

---(Re)send the whole buffer to Storm with `open`, resetting the edit tracking
---@param bufnr integer
local function send_open(bufnr)
    bufcontents[bufnr] = read_buffer(bufnr)
    buf_snapshots[bufnr] = { [0] = bufcontents[bufnr] }
    edit_log[bufnr] = {}
    last_edit_id[bufnr] = 0
    pending_hunks[bufnr] = nil
    Lsp.capture_notify({
        sym 'open',
        buf_to_sbuf[bufnr],
        vim.api.nvim_buf_get_name(bufnr),
        bufcontents[bufnr],
        M.cursor_char(bufnr),
    })
end

---Re-open every storm-mode buffer; runs when a new Storm process starts
function M.reopen_all()
    for bufnr in pairs(buf_to_sbuf) do
        if vim.api.nvim_buf_is_loaded(bufnr) then send_open(bufnr) end
    end
end

Lsp.on_start(M.reopen_all)

---Re-open the current buffer in Storm, in case it has gotten out of sync
function M.debug_reopen()
    local bufnr = vim.api.nvim_get_current_buf()
    if buf_to_sbuf[bufnr] == nil then return end
    if Lsp.is_running() then
        send_open(bufnr)
    else
        Lsp.start() -- re-opens all buffers
    end
end

---Remove all syntax coloring from the current buffer
function M.debug_uncolor() vim.api.nvim_buf_clear_namespace(vim.api.nvim_get_current_buf(), ns_id, 0, -1) end

---Set mode for buf or current buffer
---@param bufnr integer
function M.set_mode(bufnr)
    if buf_to_sbuf[bufnr] ~= nil then
        return -- already in storm-mode
    end

    -- Start first: starting re-opens the other storm-mode buffers
    Lsp.start()

    -- Storm code is indented with tabs shown 4 wide. Set before 'filetype', so
    -- that the user's FileType autocommands take precedence.
    local bo = vim.bo[bufnr]
    local indent = { tabstop = bo.tabstop, shiftwidth = bo.shiftwidth }
    if Config.indent_width then
        bo.tabstop = Config.indent_width
        bo.shiftwidth = Config.indent_width
    end

    vim.api.nvim_set_option_value('filetype', 'storm', { buf = bufnr })

    M.buf_autocmd_handlers[bufnr] = {
        vim.api.nvim_create_autocmd('CursorMoved', {
            buffer = bufnr,
            group = augroup,
            callback = M.auto_update_cursor,
        }),
        -- Syntax errors as diagnostics
        vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged' }, {
            buffer = bufnr,
            group = augroup,
            callback = function() schedule_check(bufnr) end,
        }),
    }

    local saved = { indentexpr = bo.indentexpr, indentkeys = bo.indentkeys, omnifunc = bo.omnifunc }
    if Config.indent_width then
        saved.tabstop, saved.shiftwidth = indent.tabstop, indent.shiftwidth
    end
    bo.indentexpr = "v:lua.require'storm-mode.buffer'.indentexpr()"
    bo.indentkeys = '0},0),0],o,O,!^F'
    bo.omnifunc = "v:lua.require'storm-mode.complete'.omnifunc"
    -- Like Neovim's LSP client: K shows documentation unless K is already mapped
    if not has_buf_or_global_keymap(bufnr, 'n', 'K') then
        vim.keymap.set('n', 'K', '<Plug>(storm-doc-hover)', {
            buffer = bufnr,
            desc = 'Storm: documentation for the name under the cursor',
        })
        saved.mapped_k = true
    end
    saved_settings[bufnr] = saved

    local sbufnr = next_sbufnr
    buf_to_sbuf[bufnr] = sbufnr
    sbuf_to_buf[sbufnr] = bufnr
    next_sbufnr = next_sbufnr + 1

    local token = {}
    attach_token[bufnr] = token
    vim.api.nvim_buf_attach(bufnr, false, {
        on_bytes = function(...)
            if attach_token[bufnr] ~= token then return true end
            return M.on_bytes(...)
        end,
        on_detach = function(_, b)
            if attach_token[b] == token then M.unset_mode(b) end
        end,
    })

    send_open(bufnr)
    schedule_check(bufnr) -- existing syntax errors
end

function M.manual_unset_mode()
    local bufnr = vim.api.nvim_get_current_buf()
    M.unset_mode(bufnr)
end

---@param bufnr integer
function M.unset_mode(bufnr)
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then return end

    for _, autocmd_id in ipairs(M.buf_autocmd_handlers[bufnr] or {}) do
        pcall(vim.api.nvim_del_autocmd, autocmd_id)
    end
    check_generation[bufnr] = nil
    last_point[bufnr] = nil
    if vim.api.nvim_buf_is_valid(bufnr) then vim.diagnostic.reset(require('storm-mode.errors').syntax_ns, bufnr) end

    local saved = saved_settings[bufnr]
    if saved and vim.api.nvim_buf_is_valid(bufnr) then
        local bo = vim.bo[bufnr]
        bo.indentexpr, bo.indentkeys, bo.omnifunc = saved.indentexpr, saved.indentkeys, saved.omnifunc
        if saved.tabstop then
            bo.tabstop, bo.shiftwidth = saved.tabstop, saved.shiftwidth
        end
        if saved.mapped_k then pcall(vim.keymap.del, 'n', 'K', { buffer = bufnr }) end
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end
    saved_settings[bufnr] = nil
    attach_token[bufnr] = nil

    buf_to_sbuf[bufnr] = nil
    sbuf_to_buf[sbufnr] = nil
    M.buf_autocmd_handlers[bufnr] = nil
    bufcontents[bufnr] = nil
    buf_snapshots[bufnr] = nil
    edit_log[bufnr] = nil
    last_edit_id[bufnr] = nil
    pending_hunks[bufnr] = nil

    if Lsp.is_running() then Lsp.send({ sym 'close', sbufnr }) end
    -- on_bytes returns true on the next change to self-detach (lazy).
    -- on_detach fires immediately if the buffer is deleted/unloaded.
end

---Merge one on_bytes change into the pending hunks of a buffer.
---Hunks are non-overlapping and sorted; each maps a range of the content before
---the batch (old_*) to a range of the current buffer (new_*). Changes that
---overlap or touch an existing hunk are merged into it, because the text of
---the intermediate state cannot be recovered.
---@param hunks {old_start:integer,old_end:integer,new_start:integer,new_end:integer}[]
---@param s integer 0-based start byte in current coordinates
---@param old_len integer bytes removed
---@param new_len integer bytes inserted
local function record_change(hunks, s, old_len, new_len)
    local e = s + old_len
    local delta = new_len - old_len
    local first, last
    local insert_at = #hunks + 1
    local delta_before = 0 -- size change of hunks entirely before s
    for i, h in ipairs(hunks) do
        if h.new_end < s then
            delta_before = delta_before + (h.new_end - h.new_start) - (h.old_end - h.old_start)
        elseif h.new_start > e then
            insert_at = i
            break
        else
            first = first or i
            last = i
        end
    end

    local merged
    if first == nil then
        merged = {
            old_start = s - delta_before,
            old_end = e - delta_before,
            new_start = s,
            new_end = e + delta,
        }
        table.insert(hunks, insert_at, merged)
        last = insert_at
    else
        local hf, hl = hunks[first], hunks[last]
        local delta_through = delta_before
        for i = first, last do
            local h = hunks[i]
            delta_through = delta_through + (h.new_end - h.new_start) - (h.old_end - h.old_start)
        end
        merged = {}
        if hf.new_start <= s then
            merged.new_start, merged.old_start = hf.new_start, hf.old_start
        else
            merged.new_start, merged.old_start = s, s - delta_before
        end
        local end_cur
        if hl.new_end >= e then
            end_cur, merged.old_end = hl.new_end, hl.old_end
        else
            end_cur, merged.old_end = e, e - delta_through
        end
        merged.new_end = end_cur + delta
        for _ = first, last do
            table.remove(hunks, first)
        end
        table.insert(hunks, first, merged)
        last = first
    end

    for i = last + 1, #hunks do
        hunks[i].new_start = hunks[i].new_start + delta
        hunks[i].new_end = hunks[i].new_end + delta
    end
end

---Total size of the buffer in the on_bytes byte model (final '\n' always counted,
---unlike nvim_buf_get_offset(buf, line_count) which drops it for 'noeol')
local function buffer_size(bufnr)
    local last = vim.api.nvim_buf_line_count(bufnr) - 1
    return vim.api.nvim_buf_get_offset(bufnr, last) + #vim.api.nvim_buf_get_lines(bufnr, last, last + 1, true)[1] + 1
end

---Convert a 0-based byte offset to (row, col); the buffer end maps to (line_count, 0)
local function offset_to_pos(bufnr, offset)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local lo, hi = 0, line_count - 1
    while lo < hi do -- last row whose start offset <= offset
        local mid = math.floor((lo + hi + 1) / 2)
        if vim.api.nvim_buf_get_offset(bufnr, mid) <= offset then
            lo = mid
        else
            hi = mid - 1
        end
    end
    local col = offset - vim.api.nvim_buf_get_offset(bufnr, lo)
    local line_len = #vim.api.nvim_buf_get_lines(bufnr, lo, lo + 1, true)[1]
    if col > line_len then return lo + 1, 0 end -- past the row's '\n'
    return lo, col
end

---Send one edit to Storm and update the cached content, snapshot and edit log.
---The range is in the coordinates of the current cached content.
---@param bufnr integer
---@param byte_offset integer 0-based
---@param old_len integer
---@param newstr string
local function send_edit(bufnr, byte_offset, old_len, newstr)
    local old_content = bufcontents[bufnr]
    local startchar = vim.str_utfindex(old_content, 'utf-32', byte_offset, true)
    local endchar = vim.str_utfindex(old_content, 'utf-32', byte_offset + old_len, true)

    bufcontents[bufnr] = old_content:sub(1, byte_offset) .. newstr .. old_content:sub(byte_offset + old_len + 1)

    local edit_id = last_edit_id[bufnr] + 1
    last_edit_id[bufnr] = edit_id

    local snaps = buf_snapshots[bufnr]
    snaps[edit_id] = bufcontents[bufnr]
    local n = 0
    for _ in pairs(snaps) do
        n = n + 1
    end
    if n > MAX_SNAPSHOTS then -- evict the oldest snapshot
        local min_t = math.huge
        for t in pairs(snaps) do
            if t < min_t then min_t = t end
        end
        snaps[min_t] = nil
    end

    table.insert(edit_log[bufnr], {
        id = edit_id,
        byte_offset = byte_offset,
        old_len = old_len,
        new_len = #newstr,
    })

    Lsp.send({ sym 'edit', buf_to_sbuf[bufnr], edit_id, startchar, endchar, newstr })
end

---Send the changes recorded since the last flush, reading their text from the
---buffer. Anything that reads the cached content must call this first.
---@param bufnr integer
function M.flush(bufnr)
    if pending_hunks[bufnr] == nil then return end
    -- A newly started Storm gets the whole buffer from the start hook (which
    -- drops the pending changes), so start it before computing any edit.
    Lsp.start()
    local hunks = pending_hunks[bufnr]
    pending_hunks[bufnr] = nil
    if hunks == nil or bufcontents[bufnr] == nil or not vim.api.nvim_buf_is_loaded(bufnr) then return end

    for _, h in ipairs(hunks) do
        local sr, sc = offset_to_pos(bufnr, h.new_start)
        local er, ec = offset_to_pos(bufnr, h.new_end)
        h.text = get_text(bufnr, sr, sc, er, ec)
    end
    -- Last hunk first: the old_* offsets of earlier hunks stay valid, and every
    -- edit-log entry is relative to the content right before it.
    for i = #hunks, 1, -1 do
        local h = hunks[i]
        send_edit(bufnr, h.old_start, h.old_end - h.old_start, h.text)
    end

    if #bufcontents[bufnr] ~= buffer_size(bufnr) then
        -- Should not happen; resend the whole buffer rather than drift further.
        vim.notify('storm-mode: buffer content out of sync, resending buffer', vim.log.levels.WARN)
        send_edit(bufnr, 0, #bufcontents[bufnr], read_buffer(bufnr))
    end
end

---nvim_buf_attach on_bytes callback. Only records the change: during undo/redo
---Neovim fires it after the whole undo block is applied, so the text of a
---single change can't be read here (see M.flush). Ticks aren't unique per
---callback during undo either, hence our own edit ids.
---@param bufnr integer
---@param byte_offset integer absolute 0-based byte offset of the change
---@param old_end_byte integer bytes removed
---@param new_end_byte integer bytes inserted
function M.on_bytes(
    _,
    bufnr,
    _tick,
    _start_row,
    _start_col,
    byte_offset,
    _old_end_row,
    _old_end_col,
    old_end_byte,
    _new_end_row,
    _new_end_col,
    new_end_byte
)
    if bufcontents[bufnr] == nil then return true end -- storm-mode unset: detach

    local hunks = pending_hunks[bufnr]
    if hunks == nil then
        hunks = {}
        pending_hunks[bufnr] = hunks
        vim.schedule(function() M.flush(bufnr) end)
    end
    record_change(hunks, byte_offset, old_end_byte, new_end_byte)
end

function M.quit()
    local bufs = vim.tbl_keys(buf_to_sbuf)
    for _, bufnr in ipairs(bufs) do
        M.unset_mode(bufnr)
    end
    Lsp.stop()
end

---@type table<integer, integer> last cursor position sent with `point`

---@param opts vim.AutocmdOpts
function M.auto_update_cursor(opts)
    local bufnr = opts.buf
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then return end
    M.flush(bufnr)
    local pos = M.cursor_char(bufnr)
    if pos == last_point[bufnr] then return end
    last_point[bufnr] = pos
    Lsp.send({ sym 'point', sbufnr, pos })
end

---Storm's id for a storm-mode buffer, with all changes sent; nil otherwise
---@param bufnr integer
---@return integer?
function M.storm_id(bufnr)
    if buf_to_sbuf[bufnr] == nil then return nil end
    M.flush(bufnr)
    return buf_to_sbuf[bufnr]
end

---Character offset (as used by Storm) of a position in a storm-mode buffer
---@param bufnr integer
---@param row integer 0-based
---@param col integer 0-based byte column
---@return integer?
function M.char_offset(bufnr, row, col)
    if M.storm_id(bufnr) == nil then return nil end
    return char_at(bufnr, row, col)
end

---Whether a buffer is in storm-mode; if not, tell the user how to start it.
---Checked by commands that act on a buffer, so they don't start Storm for it.
---@param bufnr? integer default: the current buffer
---@return boolean
function M.require_mode(bufnr)
    if buf_to_sbuf[bufnr or vim.api.nvim_get_current_buf()] ~= nil then return true end
    Output.notify('the buffer is not in storm-mode, see :Storm start', vim.log.levels.WARN)
    return false
end

---Send a debug request for the current buffer and print Storm's answer
---@param message_for fun(sbufnr: integer): storm-mode.lsp.message
local function debug_request(message_for)
    local sbufnr = M.storm_id(vim.api.nvim_get_current_buf())
    if sbufnr == nil then return end
    Lsp.capture(message_for(sbufnr), {
        on_done = function(text, _, err)
            if err then return end
            Output.echo(text, { kind = 'list_cmd' })
        end,
    })
end

---Print the first syntax error of the current buffer, as Storm reports it
function M.debug_error()
    debug_request(function(sbufnr) return { sym 'error', sbufnr } end)
end

---Request color information again
function M.debug_recolor()
    local bufnr = vim.api.nvim_get_current_buf()
    local sbufnr = buf_to_sbuf[bufnr]
    if sbufnr == nil then return end
    M.flush(bufnr)
    Lsp.send({ sym 'color', sbufnr })
end

---Print Storm's syntax tree of the current buffer
function M.debug_tree()
    debug_request(function(sbufnr) return { sym 'debug', sbufnr, sym 't' } end)
end

---Print Storm's view of the content of the current buffer
function M.debug_content()
    debug_request(function(sbufnr) return { sym 'debug', sbufnr, vim.NIL } end)
end

---Delete extmarks that overlap the range, ignoring marks that only touch it.
---Empty marks inside the range (left behind by deletions) are deleted too.
local function clear_range(bufnr, start_row, start_col, end_row, end_col)
    local marks = vim.api.nvim_buf_get_extmarks(
        bufnr,
        ns_id,
        { start_row, start_col },
        { end_row, end_col },
        { overlap = true, details = true }
    )
    for _, mark in ipairs(marks) do
        local mr, mc = mark[2], mark[3]
        local mer, mec = mark[4].end_row or mr, mark[4].end_col or mc
        local empty = mr == mer and mc == mec
        local ends_before = mer < start_row or (mer == start_row and mec <= start_col)
        local starts_after = mr > end_row or (mr == end_row and mc >= end_col)
        if empty or not (ends_before or starts_after) then vim.api.nvim_buf_del_extmark(bufnr, ns_id, mark[1]) end
    end
end

---Color the buffer using Storm's response for a past or current buffer state.
---Positions from Storm (which are codepoint offsets in the snapshot at edit_id)
---are transformed to byte positions in the current buffer via the edit log.
---@param sbufnr integer
---@param colors [integer, storm-mode.sym|vim.NIL][] spans; nil means no color
---@param edit_id integer the edit id we sent with the edit (0 for open)
---@param start_ch integer first codepoint Storm chose to re-colour from
function M.apply_colors(sbufnr, colors, edit_id, start_ch)
    local bufnr = sbuf_to_buf[sbufnr]
    if bufnr == nil then return end
    M.flush(bufnr) -- extmarks are placed using the cached content

    local snaps = buf_snapshots[bufnr]
    local log = edit_log[bufnr]
    if not snaps or not log then return end

    local snap = snaps[edit_id]
    if snap == nil then return end -- snapshot evicted (too many rapid edits)

    local current = bufcontents[bufnr]
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    -- The text before start_ch is not part of this update: skip it (false)
    if start_ch ~= 0 then table.insert(colors, 1, { start_ch, false }) end

    local snap_row, snap_col, snap_byte = 0, 0, 1 -- snapshot walker (char-driven)
    local cur_row, cur_col, cur_byte = 0, 0, 1 -- current-buffer walker (byte-driven)

    for _, span in ipairs(colors) do
        local span_chars = span[1]
        local hl = span[2]

        -- Advance snapshot walker; record 0-based byte range [snap_start_0, snap_end_0)
        local snap_start_0 = snap_byte - 1
        snap_row, snap_col, snap_byte = charadv_bytepos(snap, snap_row, snap_col, snap_byte, span_chars)
        local snap_end_0 = snap_byte - 1

        local cur_start_0 = hl ~= false and transform_byte_offset(log, edit_id, snap_start_0) or nil
        local cur_end_0 = cur_start_0 and transform_byte_offset(log, edit_id, snap_end_0) or nil

        if cur_start_0 ~= nil and cur_end_0 ~= nil and cur_start_0 >= 0 and cur_end_0 <= #current then
            if cur_start_0 + 1 < cur_byte then
                cur_row, cur_col, cur_byte = 0, 0, 1
            end
            cur_row, cur_col, cur_byte = advance_to_byte(current, cur_row, cur_col, cur_byte, cur_start_0 + 1)
            local start_row, start_col = cur_row, cur_col

            cur_row, cur_col, cur_byte = advance_to_byte(current, cur_row, cur_col, cur_byte, cur_end_0 + 1)
            local end_row, end_col = cur_row, cur_col

            -- A span covering the final '\n' ends at (line_count, 0), which
            -- the extmark API rejects: clamp to the end of the last line.
            if end_row >= line_count then
                end_row = line_count - 1
                end_col = #vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)[1]
            end

            if start_row < line_count then
                -- Uncolored spans clear old colors, like Emacs's storm-set-color
                clear_range(bufnr, start_row, start_col, end_row, end_col)
                if hl ~= vim.NIL then
                    -- Default gravity: text typed at the edge of a token doesn't
                    -- get its color; Storm colors the new text itself.
                    vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, start_col, {
                        hl_group = Config.highlights[tostring(hl)],
                        end_row = end_row,
                        end_col = end_col,
                    })
                end
            end
        end
    end

    -- Prune what no future color message can refer to. Storm answers in edit
    -- order, but may send several color messages for one edit (and `color`
    -- requests are answered for the latest edit), so keep this edit's snapshot.
    for id in pairs(snaps) do
        if id < edit_id then snaps[id] = nil end
    end
    edit_log[bufnr] = vim.tbl_filter(function(e) return e.id > edit_id end, log)
end

---'indentexpr': ask Storm how to indent line v:lnum. Storm answers `level n`
---(n × 'shiftwidth') or `as offset` (the column of that character).
---@return integer
function M.indentexpr()
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.v.lnum
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
    local first = line:find('[^ \t]')
    -- -1 means "use 'autoindent'" (the previous line's indent), not "keep"
    local fallback = first and vim.fn.indent(lnum) or -1
    local pos = M.char_offset(bufnr, lnum - 1, first and first - 1 or #line)
    if pos == nil then return fallback end

    local sbufnr = buf_to_sbuf[bufnr]
    local reply = Lsp.request_sync({ sym 'indent', sbufnr, pos }, INDENT_TIMEOUT_MS)
    if reply == nil or reply[1] ~= sbufnr then return fallback end

    local kind = tostring(reply[2])
    local value = reply[3] --[[@as integer]]
    if kind == 'level' then
        return value * vim.fn.shiftwidth()
    elseif kind == 'as' then
        local byte = vim.str_byteindex(bufcontents[bufnr], 'utf-32', value, false)
        local row, col = offset_to_pos(bufnr, byte)
        if row >= vim.api.nvim_buf_line_count(bufnr) then return fallback end
        local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, true)[1]
        return vim.fn.strdisplaywidth(text:sub(1, col))
    end
    return fallback
end

---Internal state for tests and debugging. Do not modify the returned values.
---@param bufnr integer
---@return {content: string?, last_edit_id: integer?}
function M._debug_state(bufnr)
    M.flush(bufnr)
    return { content = bufcontents[bufnr], last_edit_id = last_edit_id[bufnr] }
end

return M
