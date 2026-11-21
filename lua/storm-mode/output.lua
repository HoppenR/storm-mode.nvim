---Showing Storm's output with `nvim_echo` and `vim.notify`
local M = {}

---Milliseconds between attempts to run something blocked by textlock
local RETRY_MS = 20

---@param err any
---@return boolean
local function is_textlock(err) return tostring(err):find('E565', 1, true) ~= nil end

---Run `fn` now, or as soon as text is no longer locked (E565): windows can't be
---opened while an 'omnifunc' or 'indentexpr' waits for Storm. Timers run inside
---those waits, so the retry works there too.
---@param fn fun()
function M.when_unlocked(fn)
    local ok, err = pcall(fn)
    if ok then return end
    if not is_textlock(err) then error(err, 0) end
    vim.defer_fn(function() M.when_unlocked(fn) end, RETRY_MS)
end

---Strip trailing newlines and normalize line endings
---@param text string
---@return string
function M.trim(text) return (text:gsub('\r\n', '\n'):gsub('\n+$', '')) end

---@class storm-mode.output.echo_opts
---@field hl? string highlight group
---@field kind? string message kind (Neovim 0.12, see :h ui-messages), e.g. 'list_cmd' for long command output

---Print text in the message area, and add it to |:messages|
---@param text string
---@param opts? storm-mode.output.echo_opts
function M.echo(text, opts)
    opts = opts or {}
    text = M.trim(text)
    -- Storm's output arrives in arbitrary pieces; a piece can be only the
    -- indentation of a line, which is not worth a message of its own
    if text:match('^%s*$') then return end
    local echo_opts = {}
    if opts.kind and vim.fn.has('nvim-0.12') == 1 then echo_opts.kind = opts.kind end
    vim.api.nvim_echo({ { text, opts.hl } }, true, echo_opts)
end

---Show a notification, prefixed with "Storm: "
---@param text string
---@param level? integer vim.log.levels, default INFO
function M.notify(text, level)
    text = M.trim(text)
    if text:match('^%s*$') then return end
    vim.notify('Storm: ' .. text, level or vim.log.levels.INFO)
end

---Notification level for a piece of Storm output: errors while processing a
---message are errors, warnings are warnings, everything else is information
---@param text string
---@return integer
function M.level_of(text)
    if text:find('While processing', 1, true) or text:find('[%a ]+ error:') then return vim.log.levels.ERROR end
    -- "Warning: No package found ...", "WARNING storm::...: The file ... is not in a package"
    if text:lower():find('warning', 1, true) then return vim.log.levels.WARN end
    return vim.log.levels.INFO
end

---Milliseconds within which streamed lines are shown together
local BATCH_MS = 50

---Collects streamed output (arriving in arbitrary pieces) and hands it on in
---blocks of the whole lines that arrived within BATCH_MS
---@class storm-mode.output.stream
---@field private partial string text after the last newline
---@field private pending string[] whole lines not handed on yet
---@field private scheduled boolean
---@field private on_block fun(block: string)
local Stream = {}
Stream.__index = Stream

---@param on_block fun(block: string) gets one or more lines, joined by newlines
---@return storm-mode.output.stream
function M.stream(on_block)
    return setmetatable({ partial = '', pending = {}, scheduled = false, on_block = on_block }, Stream)
end

---@private
function Stream:emit()
    if #self.pending == 0 then return end
    local block = table.concat(self.pending, '\n')
    self.pending = {}
    self.on_block(block)
end

---@param chunk string
function Stream:push(chunk)
    local text = self.partial .. chunk:gsub('\r\n', '\n')
    local last = 1
    for line, stop in text:gmatch('([^\n]*)\n()') do
        table.insert(self.pending, line)
        last = stop
    end
    self.partial = text:sub(last)
    if #self.pending > 0 and not self.scheduled then
        self.scheduled = true
        vim.defer_fn(function()
            self.scheduled = false
            self:emit()
        end, BATCH_MS)
    end
end

---Hand on everything now, including a last line without a newline
function Stream:flush()
    if self.partial ~= '' then
        table.insert(self.pending, self.partial)
        self.partial = ''
    end
    self:emit()
end

return M
