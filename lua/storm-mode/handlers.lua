local M = {}

local sym = require('storm-mode.sym').literal

---Forward the message to the relevant handler
---@param message storm-mode.lsp.message
function M.resolve(message)
    if message[1] == sym 'supported' then
        vim.notify("unhandled 'supported'")
    elseif message[1] == sym 'color' then
        M.color(message)
    elseif message[1] == sym 'indent' then
        vim.notify("unhandled 'indent'")
    elseif message[1] == sym 'complete-name' then
        vim.notify("unhandled 'complete-name'")
    elseif message[1] == sym 'documentation' then
        vim.notify("unhandled 'documentation'")
    else
        assert(false, 'unhandled message ' .. tostring(message[1]))
    end
end

---Handle sym 'color' message
---@param message storm-mode.lsp.message
function M.color(message)
    vim.notify('got color?!?')
end

return M
