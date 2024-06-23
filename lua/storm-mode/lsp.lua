local M = {}

local Config = require('storm-mode.config')
local Dec = require('storm-mode.decoder')
local Enc = require('storm-mode.encoder')
local Handlers = require('storm-mode.handlers')

M.process_buffer = ''

---fix vim.NIL not being correctly typed as userdata in neovim's metadata
---@diagnostic disable-next-line: duplicate-doc-alias
---@alias vim.NIL userdata

---@alias storm-mode.lsp.message number[] | string[] | storm-mode.sym[] | vim.NIL[]

M.lsp_handle = nil ---@type uv_process_t?
M.lsp_stdin = nil ---@type uv_pipe_t?
M.lsp_stdout = nil ---@type uv_pipe_t?
M.lsp_stderr = nil ---@type uv_pipe_t?

---Returns whether the LSP appears to be running
---@return boolean
function M.is_running()
    return M.lsp_handle ~= nil and M.lsp_handle:is_active() or false
end

---Start the LSP if it is not running
function M.start()
    if not M.is_running() then
        M.start_compiler()
    end
end

-- Process all messages in the buffer, recurse until no messages are left
local function process_messages()
    local message
    message, M.process_buffer = Dec.dec_message(M.process_buffer)

    if type(message) == 'string' then
        vim.notify('Storm: ' .. message, vim.log.levels.INFO)
    elseif type(message) == 'table' then
        Handlers.resolve(message)
    elseif type(message) == 'nil' then
        return
    end

    -- Schedule processing another message
    vim.schedule(process_messages)
end

---Start the LSP in the background and set up pipes for communication
function M.start_compiler()
    assert(Config.compiler, 'cannot start compiler without a compiler path')
    assert(Config.root, 'cannot start compiler without a root path')
    M.lsp_stdin = vim.uv.new_pipe()
    M.lsp_stdout = vim.uv.new_pipe()
    M.lsp_stderr = vim.uv.new_pipe()
    local handle, _ = vim.uv.spawn(Config.compiler, {
            args = { '-r', Config.root, '--server' },
            stdio = { M.lsp_stdin, M.lsp_stdout, M.lsp_stderr },
        },
        function(code)
            vim.notify('Storm process exited with code ' .. code, vim.log.levels.WARN)
            M.lsp_stdin:close()
            M.lsp_stdout:close()
            M.lsp_stderr:close()
        end
    )

    M.lsp_handle = handle

    ---handle messages from LSP
    ---@param err? string
    ---@param data? string
    M.lsp_stdout:read_start(function(err, data)
        assert(not err, err)
        if data then
            M.process_buffer = M.process_buffer .. data
            vim.schedule(process_messages)
        else
            -- We may be in a fast_event here, prefer `print()`
            print('Storm stdout closed')
        end
    end)
end

---Send a message, starting the LSP if it is not running
---@param message storm-mode.lsp.message
function M.send(message)
    if not M.is_running() then
        M.start()
    end
    local encoded_msg = Enc.enc_message(message)
    M.lsp_stdin:write(encoded_msg)
end

return M
