local M = {}

local Config = require('storm-mode.config')
local Dec = require('storm-mode.decoder')
local Enc = require('storm-mode.encoder')
local Handlers = require('storm-mode.handlers')
local Output = require('storm-mode.output')
local Sym = require('storm-mode.sym')

M.process_buffer = ''

---fix vim.NIL not being correctly typed as userdata in neovim's metadata
---@diagnostic disable-next-line: duplicate-doc-alias
---@alias vim.NIL userdata

---@alias storm-mode.lsp.message storm-mode.sexp.list

M.lsp_handle = nil ---@type uv.uv_process_t?

---Seconds to wait for Storm to quit before killing it
local QUIT_TIMEOUT_MS = 2000

---A Storm process. Exit and output callbacks refer to their own process, so a
---process that exits after a newer one was started cannot affect the new one.
---@class storm-mode.lsp.proc
---@field handle uv.uv_process_t
---@field stdin uv.uv_pipe_t
---@field stdout uv.uv_pipe_t
---@field stderr uv.uv_pipe_t
---@field stopping boolean asked to quit: don't warn when it exits
---@field restart boolean start a new process when it has exited

---@type storm-mode.lsp.proc?
local current

---@type fun()[]
local start_hooks = {}

---Returns whether the LSP appears to be running
---@return boolean
function M.is_running() return current ~= nil and current.handle:is_active() == true end

---Run `hook` every time a new Storm process has started, before any message is
---sent to it (used to re-open buffers after a restart)
---@param hook fun()
function M.on_start(hook) table.insert(start_hooks, hook) end

---Start the LSP if it is not running
function M.start()
    if not M.is_running() then M.start_compiler() end
end

------------------------------------------------------------------------------
-- Output capture
--
-- Storm writes plain text to stdout, untagged. It handles messages in order,
-- so everything a command prints arrives before the reply to a request sent
-- right after it: that reply marks the end of the command's output.

---@class storm-mode.lsp.capture_opts
---@field on_text? fun(chunk: string) called with output as it arrives
---@field on_done? fun(text: string, reply: storm-mode.sexp[]?, err: string?) called with all output when the command is done
---@field reply? boolean the command has a reply (e.g. repl-eval), which marks the end of its output

---@class storm-mode.lsp.capture
---@field opts storm-mode.lsp.capture_opts
---@field chunks string[]

---Captures waiting for their end, oldest first. Output goes to the oldest.
---@type storm-mode.lsp.capture[]
local captures = {}

---Where output goes that belongs to no capture: the output of code started by
---`(run file)`, which Storm runs asynchronously, without a reply at the end
---@type fun(chunk: string)?
local stream

---Send output that belongs to no capture to `on_text` (until replaced, or
---Storm restarts); nil to show it as notifications again
---@param on_text fun(chunk: string)?
function M.set_output_stream(on_text) stream = on_text end

---Milliseconds to collect output that belongs to no command before showing it
local UNATTRIBUTED_DELAY_MS = 50
local unattributed = ''
local unattributed_scheduled = false

---Show output that belongs to no command; pieces arriving close together are
---shown together
---@param text string
local function on_unattributed(text)
    unattributed = unattributed .. text
    if unattributed_scheduled then return end
    unattributed_scheduled = true
    vim.defer_fn(function()
        unattributed_scheduled = false
        local pending = unattributed
        unattributed = ''
        Output.notify(pending, Output.level_of(pending))
    end, UNATTRIBUTED_DELAY_MS)
end

---@param text string
local function on_text(text)
    local capture = captures[1]
    if capture == nil then
        if stream then
            stream(text)
        else
            on_unattributed(text)
        end
        return
    end
    table.insert(capture.chunks, text)
    if capture.opts.on_text then capture.opts.on_text(text) end
end

---@param capture storm-mode.lsp.capture
---@param reply storm-mode.sexp[]?
---@param err string?
local function finish(capture, reply, err)
    -- Captures end in order, except when Storm exits and all fail at once
    for i, c in ipairs(captures) do
        if c == capture then
            table.remove(captures, i)
            break
        end
    end
    if capture.opts.on_done then capture.opts.on_done(table.concat(capture.chunks), reply, err) end
end

---Send `message` and collect the text Storm prints while handling it. Without
---a message, collect what Storm prints before handling the next one.
---@param message storm-mode.lsp.message?
---@param opts? storm-mode.lsp.capture_opts
function M.capture(message, opts)
    -- Start first: a new process captures its own startup output
    M.start()
    local capture = { opts = opts or {}, chunks = {} }
    table.insert(captures, capture)
    if capture.opts.reply and message then
        Handlers.expect(tostring(message[1]), function(reply, err) finish(capture, reply, err) end)
        M.send(message)
    else
        if message then M.send(message) end
        Handlers.expect('supported', function(_, err) finish(capture, nil, err) end)
        M.send({ Sym.literal('supported'), 'bs' })
    end
end

---M.capture, showing the output as a notification (start, open, quit)
---@param message storm-mode.lsp.message?
function M.capture_notify(message)
    M.capture(message, {
        on_done = function(text) Output.notify(text, Output.level_of(text)) end,
    })
end

---Decode and handle all complete messages received so far
function M.process_messages()
    while true do
        local message, rest, err = Dec.dec_message(M.process_buffer)
        M.process_buffer = rest
        if err ~= nil then
            Output.notify(err, vim.log.levels.WARN)
        elseif type(message) == 'string' then
            on_text(message)
        elseif type(message) == 'table' then
            local ok, handler_err = xpcall(Handlers.resolve, debug.traceback, message)
            if not ok then
                Output.notify(
                    'error handling ' .. tostring(message[1]) .. ':\n' .. tostring(handler_err),
                    vim.log.levels.ERROR
                )
            end
        else
            return
        end
    end
end

---@param err? string
---@param data? string
function M._on_stdout(err, data)
    assert(not err, err)
    if data then
        M.process_buffer = M.process_buffer .. data
        vim.schedule(M.process_messages)
    end
end

---Run the `User` autocommands StormStarted and StormStopped
---@param pattern string
---@param data table
local function fire(pattern, data)
    local ok, err = pcall(vim.api.nvim_exec_autocmds, 'User', { pattern = pattern, modeline = false, data = data })
    if not ok then
        Output.notify('error in User ' .. pattern .. ' autocommand: ' .. tostring(err), vim.log.levels.ERROR)
    end
end

---Called (in a fast event context) when a Storm process exits
---@param code integer
---@param signal integer
---@param proc storm-mode.lsp.proc
function M._on_exit(code, signal, proc)
    vim.schedule(function()
        for _, pipe in ipairs({ proc.stdin, proc.stdout, proc.stderr }) do
            if not pipe:is_closing() then pipe:close() end
        end
        if not proc.handle:is_closing() then proc.handle:close() end
        if current ~= proc then
            return -- an older process; a newer one is already running
        end

        current = nil
        M.lsp_handle = nil
        Handlers.reset('Storm exited')
        if not proc.stopping then
            Output.notify(
                string.format('exited unexpectedly (code %d, signal %d); it starts again when needed', code, signal),
                vim.log.levels.WARN
            )
        end
        fire('StormStopped', { code = code, signal = signal, expected = proc.stopping })
        if proc.restart then M.start() end
    end)
end

---Command line arguments for Storm
---@return string[]
function M.compiler_args()
    local args = { '-r', Config.root }
    for _, inc in ipairs(Config.include) do
        vim.list_extend(args, { '-I', inc.package, vim.fn.fnamemodify(inc.path, ':p') })
    end
    table.insert(args, '--server')
    return args
end

---Start the LSP in the background and set up pipes for communication
function M.start_compiler()
    if vim.uv.fs_stat(Config.compiler) == nil then error('`storm` binary not found: ' .. Config.compiler) end
    local proc = {
        stdin = vim.uv.new_pipe(),
        stdout = vim.uv.new_pipe(),
        stderr = vim.uv.new_pipe(),
        stopping = false,
        restart = false,
    }
    local handle, spawn_err = vim.uv.spawn(Config.compiler, {
        args = M.compiler_args(),
        stdio = { proc.stdin, proc.stdout, proc.stderr },
    }, function(code, signal) M._on_exit(code, signal, proc) end)
    if handle == nil then
        for _, pipe in ipairs({ proc.stdin, proc.stdout, proc.stderr }) do
            pipe:close()
        end
        error('failed to start Storm: ' .. tostring(spawn_err))
    end
    proc.handle = handle

    -- A new process knows nothing about earlier symbols or requests
    current = proc
    M.lsp_handle = handle
    M.process_buffer = ''
    Sym.reset()
    Enc._next_symid = 1
    stream = nil
    Handlers.reset('Storm restarted')

    proc.stdout:read_start(function(err, data)
        if current == proc then M._on_stdout(err, data) end
    end)
    -- Storm writes everything to stdout, but don't let a full stderr pipe block it
    proc.stderr:read_start(function(_, data)
        if data and current == proc then vim.schedule(function() Output.notify(data, vim.log.levels.WARN) end) end
    end)

    M.capture_notify(nil)
    for _, hook in ipairs(start_hooks) do
        hook()
    end
    fire('StormStarted', {})
end

---Ask Storm to quit, killing it if it does not exit in time
function M.stop()
    if not M.is_running() then return end
    local proc = current --[[@as storm-mode.lsp.proc]]
    proc.stopping = true
    -- "Terminating. Bye!" (Storm exits before answering, which ends the capture)
    M.capture_notify({ Sym.literal('quit') })
    vim.defer_fn(function()
        if proc.handle:is_active() then proc.handle:kill('sigterm') end
    end, QUIT_TIMEOUT_MS)
end

---Restart Storm; open buffers are re-opened by the start hooks
function M.restart()
    if M.is_running() then
        current.restart = true
        M.stop()
    else
        M.start()
    end
end

---Send a message, starting the LSP if it is not running
---@param message storm-mode.lsp.message
function M.send(message)
    if not M.is_running() then M.start() end
    (current --[[@as storm-mode.lsp.proc]]).stdin:write(Enc.enc_message(message))
end

---Send a request; `callback` gets the reply without its header, or nil and an
---error message if Storm exits first
---@param message storm-mode.lsp.message
---@param callback storm-mode.handlers.callback
function M.request(message, callback)
    -- Start first: starting resets the pending requests
    M.start()
    Handlers.expect(tostring(message[1]), callback)
    M.send(message)
end

---Send a request and wait for the reply. A reply arriving after the timeout is
---consumed and dropped, so later requests still get their own replies.
---@param message storm-mode.lsp.message
---@param timeout_ms integer
---@return storm-mode.sexp[]? reply
---@return string? err
function M.request_sync(message, timeout_ms)
    local done, reply, err = false, nil, nil
    M.request(message, function(r, e)
        done, reply, err = true, r, e
    end)
    vim.wait(timeout_ms, function() return done end, 5)
    if not done then return nil, 'timeout' end
    return reply, err
end

return M
