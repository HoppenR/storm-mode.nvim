---Documentation from Storm, in a split (`:Storm doc`) or a floating window (K)
local M = {}

local Complete = require('storm-mode.complete')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

---Milliseconds to wait for Storm; it may have to compile a package first
local TIMEOUT_MS = 3000
local HISTORY_SIZE = 20
local ns_id = vim.api.nvim_create_namespace('storm-mode.doc')

---@class storm-mode.doc.link
---@field row integer 0-based
---@field col integer 0-based byte column
---@field end_col integer exclusive
---@field target {name?: string, file?: string, offset?: integer, nav?: 'back'|'forward'}

---@class storm-mode.doc.view
---@field history {name: string, context: string}[]
---@field index integer current entry in history
---@field links storm-mode.doc.link[]
---@field float boolean

---@type table<integer, storm-mode.doc.view> by documentation buffer
local views = {}

---The floating window opened by K, if any
---@type {win: integer, buf: integer}?
local float

---Ask Storm for the documentation of `name`
---@param name string
---@param context string
---@return any[]? docs one entry per match (overloads); nil on error
---@return string? err
function M.query(name, context)
    local reply, err = Lsp.request_sync({ sym 'documentation', name, context }, TIMEOUT_MS)
    if reply == nil then return nil, err end
    local docs = reply[1]
    if type(docs) ~= 'table' then
        return {} -- (documentation nil): no such name
    end
    return docs
end

------------------------------------------------------------------------------
-- Rendering

---@class storm-mode.doc.builder
---@field lines string[]
---@field hls {[1]: integer, [2]: integer, [3]: integer, [4]: string}[]
---@field links storm-mode.doc.link[]
local Builder = {}
Builder.__index = Builder

---@return storm-mode.doc.builder
function Builder.new() return setmetatable({ lines = { '' }, hls = {}, links = {} }, Builder) end

---@param text string may contain newlines
---@param hl? string
---@param target? table link target
function Builder:add(text, hl, target)
    for i, part in ipairs(vim.split(text, '\n', { plain = true })) do
        if i > 1 then table.insert(self.lines, '') end
        local row = #self.lines
        local col = #self.lines[row]
        self.lines[row] = self.lines[row] .. part
        if #part > 0 then
            if hl then table.insert(self.hls, { row - 1, col, col + #part, hl }) end
            if target then
                table.insert(self.links, { row = row - 1, col = col, end_col = col + #part, target = target })
            end
        end
    end
end

local function is_str(v) return type(v) == 'string' and v ~= '' end
local function is_list(v) return type(v) == 'table' and getmetatable(v) == nil end

---A type: a link if it has a fully-qualified name, `void` otherwise
---@param b storm-mode.doc.builder
local function add_type(b, type_name, type_ref, ref)
    if type_ref == vim.NIL or type_ref == nil then
        b:add('void', 'Type')
    else
        b:add(is_str(type_name) and type_name or type_ref, 'Type', { name = type_ref })
    end
    if ref ~= vim.NIL and ref ~= nil then b:add('&') end
end

---(name type-name type-ref ref)
local function add_param(b, param)
    add_type(b, param[2], param[3], param[4])
    if is_str(param[1]) then b:add(' ' .. param[1]) end
end

---(note type-name type-ref ref), or (note) for notes without a type
local function add_note(b, note)
    if #note > 2 then
        if is_str(note[1]) then b:add(note[1] .. ' ') end
        add_type(b, note[2], note[3], note[4])
    else
        b:add(tostring(note[1]))
    end
end

---Render one entry: (name params notes visibility body pos refs)
---@param b storm-mode.doc.builder
---@param doc any[] unvalidated protocol data; every field is checked
local function add_doc(b, doc)
    local name, params, notes, vis, body, pos, refs = unpack(doc, 1, 7)
    if is_list(vis) then -- (type . title)
        b:add(tostring(vis.tail or vis[1]), 'Keyword', { name = vis[1] })
        b:add(' ')
    end
    b:add(tostring(name), 'Title')
    if is_list(params) then
        b:add('(')
        for i, param in ipairs(params) do
            if i > 1 then b:add(', ') end
            add_param(b, param)
        end
        b:add(')')
    end
    if is_list(notes) then
        for i, note in ipairs(notes) do
            b:add(i == 1 and ' ' or ', ')
            add_note(b, note)
        end
    end
    b:add(':\n\n')
    if is_list(pos) then -- (file start end)
        b:add('At: ', 'Comment')
        b:add(string.format('%s(%d-%d)', pos[1], pos[2], pos[3]), 'Underlined', { file = pos[1], offset = pos[2] })
        b:add('\n\n')
    end
    if is_str(body) then b:add(body:gsub('\r\n', '\n'):gsub('\n+$', '') .. '\n') end
    if is_list(refs) then -- ((category (name . title)...)...)
        for _, ref in ipairs(refs) do
            b:add('\n' .. tostring(ref[1]) .. ':\n', 'Title')
            for i = 2, #ref do
                local entry = ref[i]
                b:add('  ')
                b:add(tostring(entry.tail or entry[1]), 'Underlined', { name = entry[1] })
                b:add('\n')
            end
        end
    end
end

---Render documentation entries into lines, highlights and links
---@param docs any[]
---@param view? storm-mode.doc.view adds back/forward links from its history
---@return storm-mode.doc.builder
function M.render(docs, view)
    local b = Builder.new()
    for i, doc in ipairs(docs) do
        if i > 1 then b:add('\n') end
        add_doc(b, doc)
    end
    if view and (view.index > 1 or view.index < #view.history) then
        b:add('\n')
        if view.index > 1 then b:add('[back]', 'Underlined', { nav = 'back' }) end
        if view.index > 1 and view.index < #view.history then b:add('  ') end
        if view.index < #view.history then b:add('[forward]', 'Underlined', { nav = 'forward' }) end
    end
    -- No trailing empty lines
    while #b.lines > 1 and b.lines[#b.lines] == '' do
        table.remove(b.lines)
    end
    return b
end

------------------------------------------------------------------------------
-- Views

local function close_float()
    if float and vim.api.nvim_win_is_valid(float.win) then vim.api.nvim_win_close(float.win, true) end
    float = nil
end

---Size the floating window to its content
local function resize_float(win, lines)
    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line))
    end
    width = math.max(math.min(width, 80, vim.o.columns - 4), 10)
    local height = 0
    for _, line in ipairs(lines) do
        height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
    end
    height = math.max(math.min(height, 20, vim.o.lines - 4), 1)
    vim.api.nvim_win_set_config(win, { width = width, height = height })
end

---Show the current history entry of a view
---@param buf integer
---@return boolean found
local function render_view(buf)
    local view = views[buf]
    local entry = view.history[view.index]
    local docs, err = M.query(entry.name, entry.context)
    if docs == nil then
        vim.notify('Storm: documentation request failed: ' .. tostring(err), vim.log.levels.ERROR)
        return false
    end
    if #docs == 0 then
        vim.notify(string.format('Storm: no documentation for "%s"', entry.name), vim.log.levels.WARN)
        return false
    end

    local b = M.render(docs, view)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, b.lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    for _, hl in ipairs(b.hls) do
        vim.api.nvim_buf_set_extmark(buf, ns_id, hl[1], hl[2], { end_col = hl[3], hl_group = hl[4] })
    end
    view.links = b.links

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        if view.float then resize_float(win, b.lines) end
    end
    return true
end

---Open `name` in a view, adding it to the history
---@param buf integer
---@param name string
---@param context string
---@return boolean found
local function navigate(buf, name, context)
    local view = views[buf]
    local previous = view.index
    -- Drop the forward history, keep at most HISTORY_SIZE entries
    for i = #view.history, view.index + 1, -1 do
        table.remove(view.history, i)
    end
    table.insert(view.history, { name = name, context = context })
    if #view.history > HISTORY_SIZE then table.remove(view.history, 1) end
    view.index = #view.history
    if not render_view(buf) then
        table.remove(view.history)
        view.index = math.min(previous, #view.history)
        return false
    end
    return true
end

---@param buf integer
---@param delta integer -1 for back, 1 for forward
local function go(buf, delta)
    local view = views[buf]
    local index = view.index + delta
    if index < 1 or index > #view.history then return end
    view.index = index
    render_view(buf)
end

---Move the cursor to a character offset in the current buffer
---@param offset integer
local function goto_char(offset)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local content = table.concat(lines, '\n') .. '\n'
    local byte = vim.str_byteindex(content, 'utf-32', offset, false)
    local row, line_start = 0, 0
    for i = 1, byte do
        if content:byte(i) == 0x0A then
            row = row + 1
            line_start = i
        end
    end
    row = math.min(row, #lines - 1)
    vim.api.nvim_win_set_cursor(0, { row + 1, math.max(byte - line_start, 0) })
end

---Follow the link under the cursor in a documentation view
function M.follow_link()
    local buf = vim.api.nvim_get_current_buf()
    local view = views[buf]
    if view == nil then return end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2]
    for _, link in ipairs(view.links) do
        if link.row == row and col >= link.col and col < link.end_col then
            local nav, name, file = link.target.nav, link.target.name, link.target.file
            if nav then
                go(buf, nav == 'back' and -1 or 1)
            elseif name then
                navigate(buf, name, view.history[view.index].context)
            elseif file then
                if vim.fn.filereadable(file) == 0 then
                    vim.notify('Storm: cannot open ' .. file, vim.log.levels.WARN)
                    return
                end
                if view.float then
                    close_float()
                else
                    vim.cmd('wincmd p')
                end
                -- Not :edit, which fails (E37) if the file is loaded and modified
                local target_buf = vim.fn.bufadd(vim.fn.fnamemodify(file, ':p'))
                vim.fn.bufload(target_buf)
                vim.bo[target_buf].buflisted = true
                vim.api.nvim_win_set_buf(0, target_buf)
                goto_char(link.target.offset)
            end
            return
        end
    end
end

---Create a documentation buffer with its keymaps
---@param is_float boolean
---@return integer buf
local function new_view_buffer(is_float)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'storm-doc'
    views[buf] = { history = {}, index = 0, links = {}, float = is_float }
    local function map(lhs, fn, desc) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc }) end
    map('<CR>', M.follow_link, 'Storm: follow link')
    map('<C-o>', function() go(buf, -1) end, 'Storm: previous documentation')
    map('<C-i>', function() go(buf, 1) end, 'Storm: next documentation')
    map('q', '<Cmd>close<CR>', 'Storm: close documentation')
    vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        callback = function() views[buf] = nil end,
    })
    return buf
end

---Show documentation for `name` in a split, reusing an open documentation split
---@param name string
---@param context? string defaults to the current buffer's directory
function M.show(name, context)
    context = context or Complete.context()
    local buf
    for b, view in pairs(views) do
        if not view.float and vim.api.nvim_buf_is_valid(b) then buf = b end
    end
    local created = buf == nil
    buf = buf or new_view_buffer(false)
    if not navigate(buf, name, context) then
        if created then vim.api.nvim_buf_delete(buf, { force = true }) end
        return
    end
    local win = vim.fn.win_findbuf(buf)[1]
    if win then
        vim.api.nvim_set_current_win(win)
    else
        vim.api.nvim_open_win(buf, true, { split = 'below' })
        vim.wo.wrap = true
        vim.wo.linebreak = true
    end
end

---Show documentation for the name under the cursor in a floating window, or
---move into the window if it is open
function M.hover()
    if float and vim.api.nvim_win_is_valid(float.win) then
        vim.api.nvim_set_current_win(float.win)
        return
    end
    if not require('storm-mode.buffer').require_mode() then return end
    local name = Complete.name_at_cursor()
    if name == nil then
        vim.notify('Storm: no name under the cursor', vim.log.levels.WARN)
        return
    end
    local buf = new_view_buffer(true)
    if not navigate(buf, name, Complete.context()) then
        vim.api.nvim_buf_delete(buf, { force = true })
        return
    end
    local win = vim.api.nvim_open_win(buf, false, {
        relative = 'cursor',
        row = 1,
        col = 0,
        width = 10,
        height = 1,
        style = 'minimal',
        border = 'rounded',
        focusable = true,
    })
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    resize_float(win, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    float = { win = win, buf = buf }

    -- Close when the cursor moves in the source buffer. (Entering the float
    -- fires BufLeave/WinLeave in the source, so those can't be used.)
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter' }, {
        buffer = vim.api.nvim_get_current_buf(),
        callback = function()
            if float == nil or float.buf ~= buf then
                return true -- this float is gone: remove the autocmd
            end
            if vim.api.nvim_get_current_win() ~= win then
                close_float()
                return true
            end
        end,
    })
    vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(win),
        once = true,
        callback = function()
            if float and float.win == win then float = nil end
        end,
    })
end

---The floating window opened by K, for tests
---@return {win: integer, buf: integer}?
function M._float() return float end

return M
