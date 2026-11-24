-- Errors reported by Storm, as diagnostics and in the quickfix list. Storm
-- reports locations as character offsets:
--     @/path/to/file.bs(44-45): Syntax error: Unexpected '}'. Expected:
--       ";"
--     @./(2-3): Syntax error: ...      (an expression given to :Storm eval)
local M = {}

local Lsp = require('storm-mode.lsp')
local Output = require('storm-mode.output')
local sym = require('storm-mode.sym').literal

---Syntax errors from `(error id)`, per storm-mode buffer
M.syntax_ns = vim.api.nvim_create_namespace('storm-mode.syntax')
---Errors from compiling code (`:Storm run`, `:Storm reload`)
M.compile_ns = vim.api.nvim_create_namespace('storm-mode.compile')

local QF_TITLE = 'Storm errors'
---How many of the expected tokens of a syntax error to show
local EXPECTED_SHOWN = 5

---@class storm-mode.errors.item
---@field filename string absolute path
---@field lnum integer 1-based
---@field col integer 1-based byte column
---@field end_lnum? integer
---@field end_col? integer exclusive
---@field text string
---@field type 'E'|'I' 'I' for `here` (another location of the previous error)

---Text of a file: from a loaded buffer if there is one, otherwise from disk
---@param path string
---@return string[]?
local function file_lines(path)
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) end
    if vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path) end
    return nil
end

---Convert a character offset to a 1-based line and byte column
---@param lines string[]
---@param offset integer
---@return integer lnum, integer col
local function char_to_lnum_col(lines, offset)
    for i, line in ipairs(lines) do
        local chars = vim.str_utfindex(line, 'utf-32')
        if offset <= chars then return i, vim.str_byteindex(line, 'utf-32', offset, false) + 1 end
        offset = offset - chars - 1 -- the newline
    end
    return #lines, 1
end

---"Unexpected '}'. Expected:" followed by indented tokens → one line
---@param text string the message after the location
---@param tokens string[]
---@return string
local function condense_expected(text, tokens)
    if #tokens == 0 then return (text:gsub('%s*Expected:$', '')) end
    local shown = vim.list_slice(tokens, 1, EXPECTED_SHOWN)
    local more = #tokens > EXPECTED_SHOWN and string.format(' (+%d more)', #tokens - EXPECTED_SHOWN) or ''
    return text .. ' ' .. table.concat(shown, ', ') .. more
end

---Find error locations in Storm's output. Locations that are not files (such
---as positions in an evaluated expression) are skipped.
---@param text string
---@return storm-mode.errors.item[]
function M.parse(text)
    local lines = vim.split(text:gsub('\r\n', '\n'), '\n', { plain = true })
    local items = {}
    local cache = {}
    local i = 1
    while i <= #lines do
        local file, from, to, msg = lines[i]:match('@([^(\t]+)%((%d+)%-?(%d*)%): (.*)$')
        i = i + 1
        if file and (msg:match('^[%a ]+ error:') or msg == 'here') then
            -- An "Expected:" list follows on indented lines
            local tokens = {}
            if msg:match('Expected:$') then
                while i <= #lines and lines[i]:match('^%s+%S') do
                    table.insert(tokens, vim.trim(lines[i]))
                    i = i + 1
                end
            end
            local path = vim.fn.fnamemodify(file, ':p')
            if cache[path] == nil then cache[path] = vim.fn.isdirectory(path) == 0 and file_lines(path) or false end
            local flines = cache[path]
            if flines then
                local lnum, col = char_to_lnum_col(flines, tonumber(from) --[[@as integer]])
                local item = {
                    filename = path,
                    lnum = lnum,
                    col = col,
                    text = condense_expected(msg, tokens),
                    type = msg == 'here' and 'I' or 'E',
                }
                if to ~= '' then
                    item.end_lnum, item.end_col = char_to_lnum_col(flines, tonumber(to) --[[@as integer]])
                end
                table.insert(items, item)
            end
        end
    end
    return items
end

---@param item storm-mode.errors.item
---@return vim.Diagnostic.Set
local function to_diagnostic(item)
    return {
        lnum = item.lnum - 1,
        col = item.col - 1,
        end_lnum = (item.end_lnum or item.lnum) - 1,
        end_col = (item.end_col or item.col) - 1,
        message = item.text,
        severity = item.type == 'I' and vim.diagnostic.severity.HINT or vim.diagnostic.severity.ERROR,
        source = 'storm',
    }
end

---Replace the diagnostics in `ns` of the files in `scope` and in `items`. Files
---that aren't open get an unloaded buffer.
---@param ns integer
---@param items storm-mode.errors.item[]
---@param scope (integer|string)[] buffer numbers or paths
function M.set_diagnostics(ns, items, scope)
    ---@type table<integer, vim.Diagnostic.Set[]>
    local by_buf = {}
    for _, file in ipairs(scope) do
        by_buf[
            type(file) == 'number' and file or vim.fn.bufadd(file --[[@as string]])
        ] = {}
    end
    for _, item in ipairs(items) do
        local bufnr = vim.fn.bufadd(item.filename)
        by_buf[bufnr] = by_buf[bufnr] or {}
        table.insert(by_buf[bufnr], to_diagnostic(item))
    end
    for bufnr, diagnostics in pairs(by_buf) do
        if vim.api.nvim_buf_is_valid(bufnr) then vim.diagnostic.set(ns, bufnr, diagnostics) end
    end
end

---Ask Storm for the first syntax error of a storm-mode buffer and update its
---diagnostics
---@param bufnr integer
---@param on_done? fun() called when the diagnostics are updated
---@return boolean sent false if the buffer is not in storm-mode
function M.check(bufnr, on_done)
    local id = require('storm-mode.buffer').storm_id(bufnr)
    if id == nil then return false end
    Lsp.capture({ sym 'error', id }, {
        on_done = function(text, _, err)
            if err or not vim.api.nvim_buf_is_valid(bufnr) then return end
            M.set_diagnostics(M.syntax_ns, M.parse(text), { bufnr })
            if on_done then on_done() end
        end,
    })
    return true
end

---Update compile errors from the output of `:Storm run`/`:Storm reload`
---@param text string output
---@param scope (integer|string)[] files whose old compile errors are replaced
function M.from_compile_output(text, scope)
    local items = M.parse(text)
    M.set_diagnostics(M.compile_ns, items, scope)
    local count = #vim.tbl_filter(function(item) return item.type == 'E' end, items)
    if count > 0 then
        Output.notify(
            string.format('%d error%s, see :Storm errors', count, count == 1 and '' or 's'),
            vim.log.levels.WARN
        )
    end
end

---All Storm diagnostics as quickfix items
---@return vim.quickfix.entry[]
local function quickfix_items()
    local items = {}
    for _, ns in ipairs({ M.syntax_ns, M.compile_ns }) do
        -- Diagnostics can outlive their buffer, and
        -- setqflist fails on an item for a buffer that doesn't exist (E92)
        local diagnostics = vim.tbl_filter(
            function(d) return vim.api.nvim_buf_is_valid(d.bufnr) end,
            vim.diagnostic.get(nil, { namespace = ns })
        )
        vim.list_extend(items, vim.diagnostic.toqflist(diagnostics))
    end
    return items
end

---Put Storm's diagnostics in the quickfix list and open it, replacing an
---existing "Storm errors" list (emptied and closed when there are no errors)
---@return integer count number of entries
function M.to_quickfix()
    local items = quickfix_items()
    -- The list, the window and the message change together: the window may have
    -- to wait for a text lock (E565), and the list shouldn't get ahead of it
    Output.when_unlocked(function()
        local ours = vim.fn.getqflist({ title = 0 }).title == QF_TITLE
        if #items == 0 then
            if ours then
                vim.cmd('cclose')
                vim.fn.setqflist({}, 'r', { title = QF_TITLE, items = {} })
            end
            Output.notify('no errors')
            return
        end
        vim.cmd('copen')
        vim.fn.setqflist({}, ours and 'r' or ' ', { title = QF_TITLE, items = items })
    end)
    return #items
end

---`:Storm errors`: check the current buffer, then show all errors in quickfix
function M.show()
    if not M.check(vim.api.nvim_get_current_buf(), M.to_quickfix) then M.to_quickfix() end
end

return M
