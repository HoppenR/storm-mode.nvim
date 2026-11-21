---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Matching replies to requests, and attributing Storm's (untagged) text output
-- to the command that caused it. Without Storm: Lsp.send/start are stubbed, and
-- replies and text are fed to the message processing as Storm would send them.
local Enc = require('storm-mode.encoder')
local Handlers = require('storm-mode.handlers')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

---Feed Storm's stdout: strings are text output, tables are messages
local function storm_says(...)
    for _, item in ipairs({ ... }) do
        Lsp.process_buffer = Lsp.process_buffer .. (type(item) == 'string' and item or Enc.enc_message(item))
    end
    Lsp.process_messages()
end

local SENTINEL_REPLY = { sym 'supported', 'bs', sym 't' }

describe('output capture', function()
    local send_stub, start_stub, out

    before_each(function()
        send_stub = stub.new(Lsp, 'send')
        start_stub = stub.new(Lsp, 'start')
        -- Ends captures left unfinished by earlier tests, as Storm exiting does
        Handlers.reset('test')
        Lsp.process_buffer = ''
        Lsp.set_output_stream(nil)
        out = StormTest.record()
    end)

    after_each(function()
        out.restore()
        send_stub:revert()
        start_stub:revert()
    end)

    it('collects the output of a command until the reply to the sentinel', function()
        local result
        Lsp.capture({ sym 'error', 1 }, { on_done = function(text) result = text end })
        -- The command, then the sentinel
        assert.are.equal(sym 'error', send_stub.calls[1].vals[1][1])
        assert.are.same({ sym 'supported', 'bs' }, send_stub.calls[2].vals[1])

        storm_says('No ', 'errors.\n')
        assert.is_nil(result, 'not done before the sentinel reply')
        storm_says(SENTINEL_REPLY)
        assert.are.equal('No errors.\n', result)
    end)

    it('attributes output to captures in order', function()
        local results = {}
        Lsp.capture({ sym 'error', 1 }, { on_done = function(text) results.first = text end })
        Lsp.capture({ sym 'debug', 1, sym 't' }, { on_done = function(text) results.second = text end })
        storm_says('first output\n', SENTINEL_REPLY, 'second output\n', SENTINEL_REPLY)
        assert.are.same({ first = 'first output\n', second = 'second output\n' }, results)
    end)

    it('streams output as it arrives', function()
        local chunks = {}
        Lsp.capture({ sym 'run', 1, 5 }, {
            reply = true,
            on_text = function(chunk) table.insert(chunks, chunk) end,
        })
        storm_says('a\n')
        storm_says('b\n')
        assert.are.same({ 'a\n', 'b\n' }, chunks)
    end)

    it('ends at the command reply for commands that have one', function()
        local text, reply
        Lsp.capture({ sym 'repl-eval', 'bs', '1 + 2', vim.NIL }, {
            reply = true,
            on_done = function(t, r)
                text, reply = t, r
            end,
        })
        assert.are.equal(1, #send_stub.calls, 'no sentinel')
        storm_says('printed by eval\n', { sym 'repl-eval', '3' })
        assert.are.equal('printed by eval\n', text)
        assert.are.same({ '3' }, reply)
    end)

    it('handles commands without output', function()
        local result
        Lsp.capture({ sym 'error', 99 }, { on_done = function(text) result = text end })
        storm_says(SENTINEL_REPLY)
        assert.are.equal('', result)
    end)

    it('shares the sentinel queue with other `supported` requests', function()
        local supported, captured
        Lsp.request({ sym 'supported', 'bs' }, function(r) supported = r end)
        Lsp.capture({ sym 'error', 1 }, { on_done = function(text) captured = text end })
        storm_says(SENTINEL_REPLY, 'No errors.\n', SENTINEL_REPLY)
        assert.are.same({ 'bs', sym 't' }, supported)
        assert.are.equal('No errors.\n', captured)
    end)

    it('ends captures with an error, keeping their output, when Storm exits', function()
        local text, err
        Lsp.capture({ sym 'quit' }, {
            on_done = function(t, _, e)
                text, err = t, e
            end,
        })
        storm_says('Terminating. Bye!\n')
        Handlers.reset('Storm exited')
        assert.are.equal('Terminating. Bye!\n', text)
        assert.are.equal('Storm exited', err)
    end)

    ---Notifications containing `text` (late output of an earlier spec file's
    ---Storm process may be notified too)
    local function notifications_with(text)
        return vim.tbl_filter(function(n) return n.msg:find(text, 1, true) ~= nil end, out.notifications)
    end

    it('shows output that belongs to no command as one notification', function()
        storm_says('line one\n', 'line two\n')
        assert.is_true(vim.wait(500, function() return #notifications_with('line one') > 0 end, 10))
        assert.are.same(
            { { msg = 'Storm: line one\nline two', level = vim.log.levels.INFO } },
            notifications_with('line one')
        )
    end)

    it('shows errors from processing a message as errors', function()
        storm_says('While processing (debug):\nMemory access error\n')
        assert.is_true(vim.wait(500, function() return #notifications_with('Memory access') > 0 end, 10))
        assert.are.equal(vim.log.levels.ERROR, notifications_with('Memory access')[1].level)
    end)

    it('sends output that belongs to no command to the output stream', function()
        local streamed = {}
        Lsp.set_output_stream(function(chunk) table.insert(streamed, chunk) end)
        local captured
        Lsp.capture({ sym 'error', 1 }, { on_done = function(text) captured = text end })
        storm_says('No errors.\n', SENTINEL_REPLY, 'program output\n')
        assert.are.equal('No errors.\n', captured)
        assert.are.same({ 'program output\n' }, streamed)
        vim.wait(100)
        -- (Late output of an earlier spec file's Storm process may be notified)
        assert.is_false(out.find('program output'), 'streamed output is not notified')
    end)
end)

describe('requests', function()
    local send_stub, start_stub

    before_each(function()
        send_stub = stub.new(Lsp, 'send')
        start_stub = stub.new(Lsp, 'start')
        Handlers.pending = {}
    end)

    after_each(function()
        send_stub:revert()
        start_stub:revert()
    end)

    it('matches replies to requests of the same kind in order', function()
        local got = {}
        Lsp.request({ sym 'complete-name', 'a', '/' }, function(r) table.insert(got, { 'first', r }) end)
        Lsp.request({ sym 'indent', 1, 0 }, function(r) table.insert(got, { 'indent', r }) end)
        Lsp.request({ sym 'complete-name', 'b', '/' }, function(r) table.insert(got, { 'second', r }) end)
        assert.stub(send_stub).was_called(3)

        Handlers.resolve({ sym 'complete-name', 'a1' })
        Handlers.resolve({ sym 'indent', 1, sym 'level', 2 })
        Handlers.resolve({ sym 'complete-name', 'b1', 'b2' })
        assert.are.same({
            { 'first', { 'a1' } },
            { 'indent', { 1, sym 'level', 2 } },
            { 'second', { 'b1', 'b2' } },
        }, got)
    end)

    it('fails pending requests when Storm goes away', function()
        local got
        Lsp.request({ sym 'documentation', 'x', '/' }, function(r, err) got = { r, err } end)
        Handlers.reset('Storm exited')
        assert.are.same({ nil, 'Storm exited' }, got)
        assert.are.same({}, Handlers.pending)
    end)

    it('request_sync times out, and the late reply does not reach the next request', function()
        local reply, err = Lsp.request_sync({ sym 'indent', 1, 0 }, 20)
        assert.is_nil(reply)
        assert.are.equal('timeout', err)

        local got
        Lsp.request({ sym 'indent', 1, 5 }, function(r) got = r end)
        Handlers.resolve({ sym 'indent', 1, sym 'level', 0 }) -- late reply to the first request
        assert.is_nil(got)
        Handlers.resolve({ sym 'indent', 1, sym 'level', 1 })
        assert.are.same({ 1, sym 'level', 1 }, got)
    end)

    it('request_sync returns a reply that arrives while waiting', function()
        vim.defer_fn(function() Handlers.resolve({ sym 'repl-available', 'bs' }) end, 10)
        local reply = Lsp.request_sync({ sym 'repl-available' }, 1000)
        assert.are.same({ 'bs' }, reply)
    end)

    it('reports unknown messages instead of failing', function()
        local out = StormTest.record()
        assert.has_no.errors(function() Handlers.resolve({ sym 'something-new', 1 }) end)
        out.restore()
        assert.are.same(
            { { msg = 'Storm: unhandled message: something-new', level = vim.log.levels.WARN } },
            out.notifications
        )
    end)

    it('keeps processing messages after a handler error', function()
        local Enc = require('storm-mode.encoder')
        local out = StormTest.record()
        local got
        Lsp.request({ sym 'indent', 1, 0 }, function() error('boom') end)
        Lsp.request({ sym 'complete-name', '', '/' }, function(r) got = r end)
        local indent_msg = Enc.enc_message({ sym 'indent', 1, sym 'level', 0 })
        local complete_msg = Enc.enc_message({ sym 'complete-name', 'ok' })
        Lsp.process_buffer = indent_msg .. complete_msg
        Lsp.process_messages()
        out.restore()
        assert.are.same({ 'ok' }, got)
        assert.matches('boom', out.text())
        assert.are.equal(vim.log.levels.ERROR, out.notifications[1].level)
        assert.are.equal('', Lsp.process_buffer)
    end)
end)
