---@diagnostic disable: duplicate-set-field
-- Helper script for setting non-default configuration options before running
-- the tests.
-- If defaults are preferred, there is no need to set the environment variables.

-- If needed, run the tests like this, or simply edit the file paths below.
-- ```
-- $ export STORM_COMPILER=~/projects/storm-lang/storm
-- $ export STORM_ROOT=~/projects/storm-lang/root/
-- $ busted
-- ```

require('storm-mode').setup({
    compiler = os.getenv('STORM_COMPILER'), -- default: "/usr/bin/storm"
    root = os.getenv('STORM_ROOT'), -- default: "/usr/lib/storm/"
})

----- SHARED FUNCTIONS -----

---Helper function to match the first element of a message
---@param expected {[1]: storm-mode.sym, ['n']: integer}
---@return fun(actual: storm-mode.lsp.message): boolean
local function is_messagetype(_, expected)
    return function(actual) return expected[1] == actual[1] end
end
require('luassert'):register('matcher', 'messagetype', is_messagetype)

---Record vim.notify and nvim_echo calls (Storm's output) for assertions.
---Usage: `local out = StormTest.record()` ... `out.restore()`
---@class storm-mode.test.recording
---@field notifications {msg: string, level: integer}[]
---@field echoes {text: string, kind: string?}[]
---@field restore fun()
---@field text fun(): string everything echoed and notified, one entry per line
---@field find fun(pattern: string): boolean whether some output matches
---@field wait_for fun(pattern: string, ms?: integer): boolean

---@diagnostic disable-next-line: lowercase-global
StormTest = {}

---@return storm-mode.test.recording
function StormTest.record()
    local rec = { notifications = {}, echoes = {} }
    local orig_notify, orig_echo = vim.notify, vim.api.nvim_echo
    vim.notify = function(msg, level) table.insert(rec.notifications, { msg = msg, level = level }) end
    vim.api.nvim_echo = function(chunks, _, opts)
        local text = {}
        for _, chunk in ipairs(chunks) do
            table.insert(text, chunk[1])
        end
        table.insert(rec.echoes, { text = table.concat(text), kind = opts and opts.kind })
    end
    function rec.restore()
        vim.notify, vim.api.nvim_echo = orig_notify, orig_echo
    end
    function rec.text()
        local all = {}
        for _, e in ipairs(rec.echoes) do
            table.insert(all, e.text)
        end
        for _, n in ipairs(rec.notifications) do
            table.insert(all, n.msg)
        end
        return table.concat(all, '\n')
    end
    function rec.find(pattern) return rec.text():find(pattern) ~= nil end
    function rec.wait_for(pattern, ms)
        return vim.wait(ms or 5000, function() return rec.find(pattern) end, 20)
    end
    return rec
end
