local M = {}

local sym = require('storm-mode.sym').literal
local Buffer = require('storm-mode.buffer')

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
    local it = vim.iter(message):skip(1) -- Skip header
    ---@type integer, integer, integer
    local bufnr, edit_id, start = it:next(), it:next(), it:next()
    print('sbufid', bufnr, 'eid', edit_id, 'start', start)

    ---@type [integer, storm-mode.sym][]
    local colors = {}
    while it:peek() ~= nil do
        table.insert(colors, { it:next(), it:next() })
    end

    Buffer.color_buffer(bufnr, colors)
end

return M
