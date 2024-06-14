local M = {}

local sym = require('storm-mode.sym').literal
local Buffer = require('storm-mode.buffer')

---Forward the message to the relevant handler
---@param message storm-mode.lsp.message
function M.resolve(message)
    local it = vim.iter(message)
    local header = it:next()
    if header == sym 'supported' then
        vim.notify("unhandled 'supported'")
    elseif header == sym 'color' then
        M.color(it)
    elseif header == sym 'indent' then
        vim.notify("unhandled 'indent'")
    elseif header == sym 'complete-name' then
        vim.notify("unhandled 'complete-name'")
    elseif header == sym 'documentation' then
        vim.notify("unhandled 'documentation'")
    else
        assert(false, 'unhandled message ' .. tostring(header))
    end
end

---Handle sym 'color' message
---@param it Iter
function M.color(it)
    ---@type integer, integer, integer
    local bufnr, edit_id, start = it:next(), it:next(), it:next()

    ---@type [integer, storm-mode.sym][]
    local colors = {}
    while it:peek() ~= nil do
        table.insert(colors, { it:next(), it:next() })
    end

    Buffer.color_buffer(bufnr, colors, edit_id, start)
end

return M
