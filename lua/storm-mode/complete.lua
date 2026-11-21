---Name completion with Storm's `complete-name` (no local variables)
local M = {}

local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

---Milliseconds to wait for Storm; it may have to compile a package first
local TIMEOUT_MS = 2000
---Characters that can be part of a name, e.g. `core.Str`
local NAME_CHAR = '[%w_.]'

---Last query and its result
---@type {query: string?, context: string?, names: string[]}
local cache = { names = {} }

Lsp.on_start(function() cache = { names = {} } end)

---Context sent with name queries: the directory of the buffer's file, which
---lets Storm resolve names in that package
---@param bufnr? integer
---@return string
function M.context(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr or 0)
    if name ~= '' and not name:match('^%a[%w+.-]*://') then return vim.fn.fnamemodify(name, ':p:h') end
    return vim.fn.getcwd()
end

---Names that Storm suggests for `query` (e.g. "core.St" → "core.Str", ...)
---@param query string
---@param context? string defaults to M.context()
---@return string[]
function M.names(query, context)
    context = context or M.context()
    if cache.query == query and cache.context == context then return cache.names end
    local reply = Lsp.request_sync({ sym 'complete-name', query, context }, TIMEOUT_MS)
    if reply == nil then
        return {} -- don't cache failures, Storm may just have been busy
    end
    local names = {}
    for _, name in ipairs(reply) do
        if type(name) == 'string' then table.insert(names, name) end
    end
    table.sort(names)
    cache = { query = query, context = context, names = names }
    return names
end

---Byte range of the name around column `col` (0-based) in `line`
---@param line string
---@param col integer
---@return integer? start 1-based
---@return integer? stop 1-based, inclusive
local function name_range(line, col)
    local s = col + 1
    if not line:sub(s, s):match(NAME_CHAR) then return nil end
    local e = s
    while s > 1 and line:sub(s - 1, s - 1):match(NAME_CHAR) do
        s = s - 1
    end
    while e < #line and line:sub(e + 1, e + 1):match(NAME_CHAR) do
        e = e + 1
    end
    return s, e
end

---The name under the cursor, including dots (`core.Str`)
---@return string?
function M.name_at_cursor()
    local line = vim.api.nvim_get_current_line()
    local s, e = name_range(line, vim.api.nvim_win_get_cursor(0)[2])
    if s == nil then return nil end
    local name = line:sub(s, e):gsub('^%.+', ''):gsub('%.+$', '')
    return name ~= '' and name or nil
end

---Completion items for `base`; overloads (`clamp(core.Int, ...)`) are grouped
---into one item per name, with the signatures in `info`
---@param base string
---@return table[]
function M.items(base)
    local items, by_word = {}, {}
    for _, full in ipairs(M.names(base)) do
        local word = full:match('^[^(]*')
        local item = by_word[word]
        if item == nil then
            item = { word = word, abbr = full, menu = '[Storm]', signatures = {} }
            by_word[word] = item
            table.insert(items, item)
        end
        table.insert(item.signatures, full)
    end
    for _, item in ipairs(items) do
        if #item.signatures > 1 then item.abbr = item.word .. '(…)' end
        item.info = table.concat(item.signatures, '\n')
        item.signatures = nil
    end
    return items
end

---'omnifunc' for storm-mode buffers (<C-x><C-o>)
---@param findstart integer
---@param base string
---@return integer|table[]
function M.omnifunc(findstart, base)
    if findstart == 1 then
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2] -- cursor is after the text
        local start = col
        while start > 0 and line:sub(start, start):match(NAME_CHAR) do
            start = start - 1
        end
        return start
    end
    return M.items(base)
end

---Completion for `:Storm doc {name}`. Names can contain spaces
---(`clamp(core.Byte, core.Byte)`) while the command line only replaces the last
---word, so only the part after `full_lead`'s last word is returned.
---@param arg_lead string the word being completed
---@param full_lead string everything typed after `:Storm doc `
---@return string[]
function M.complete_cmdline(arg_lead, full_lead)
    local result = {}
    local skip = #full_lead - #arg_lead
    for _, name in ipairs(M.names(full_lead)) do
        if vim.startswith(name, full_lead) then table.insert(result, name:sub(skip + 1)) end
    end
    return result
end

return M
