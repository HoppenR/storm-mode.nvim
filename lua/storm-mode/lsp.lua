local M = {}

M.process_buffer = ''

---@alias storm-mode.lsp.message table<number | string | storm-mode.sym>

M.lsp_handle = nil ---@type uv_process_t?
M.lsp_stdin = nil ---@type uv_pipe_t?
M.lsp_stdout = nil ---@type uv_pipe_t?
M.lsp_stderr = nil ---@type uv_pipe_t?

---Returns whether the LSP appears to be running
---@return boolean
function M.is_running()
    if M.lsp_stdin == nil then
        return false
    end
    local closed = M.lsp_stdin:is_closing()
    return closed ~= nil and not closed
end

---Stop the LSP if it is running
function M.stop()
    if M.is_running() and M.lsp_handle ~= nil then
        M.lsp_handle:close()
    end
end

---Start the LSP if it is not running
function M.start()
    if not M.is_running() then
        M.start_compiler()
    end
end

---Start the LSP in the background and set up pipes for communication
function M.start_compiler()
    M.lsp_stdin = vim.uv.new_pipe()
    M.lsp_stdout = vim.uv.new_pipe()
    M.lsp_stderr = vim.uv.new_pipe()
    local handle, _ = vim.uv.spawn(
        require('storm-mode.config').compiler,
        {
            args = {
                '-r',
                require('storm-mode.config').root,
                '--server',
            },
            stdio = {
                M.lsp_stdin,
                M.lsp_stdout,
                M.lsp_stderr,
            },
        },
        function(code)
            vim.notify('Storm process exited with code ' .. code, vim.log.levels.WARN)
            M.lsp_stdin:close()
            M.lsp_stdout:close()
            M.lsp_stderr:close()
        end
    )

    M.lsp_handle = handle

    M.lsp_stdout:read_start(
    ---handle messages from LSP
    ---@param err string?
    ---@param data string?
        function(err, data)
            assert(not err, err)
            if data then
                local dec_data
                dec_data, M.process_buffer = require('storm-mode.decoder').dec_message(M.process_buffer .. data)

                if type(dec_data) == 'string' then
                    vim.notify('Lsp message: ' .. dec_data, vim.log.levels.INFO)
                elseif type(dec_data) == 'table' then
                    require('storm-mode.handlers').resolve(dec_data)
                end
            else
                vim.notify('Storm stdout closed', vim.log.levels.WARN)
            end
        end
    )
end

---Send a message, starting the LSP if it is not running
---@param message storm-mode.lsp.message
function M.send(message)
    if not M.is_running() then
        M.start()
    end
    local encoded_msg = require('storm-mode.encoder').enc_message(message)
    M.lsp_stdin:write(encoded_msg)
end

return M
