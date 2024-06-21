local M = {}

local sym = require('storm-mode.sym').literal

---@type table<string, function>
M.waiting_jobs = {}

---Forward the message to the relevant handler
---@param message storm-mode.lsp.message
function M.resolve(message)
    local it = vim.iter(message)
    local header = it:next()
    if header == sym 'supported' then
        M.supported(it)
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

    require('storm-mode.buffer').apply_colors(bufnr, colors, edit_id, start)
end

---Handle sym 'supported' message
---@param it Iter
function M.supported(it)
    ---@type integer
    local bufft = it:next()
    ---@type function<boolean, nil>
    local callback = M.waiting_jobs[bufft]
    local result = it:next()
    if callback ~= nil then
        ---@type boolean
        local supported = result == sym 't'
        callback(supported)
    else
        vim.notify("no callback added for 'supported query")
    end
    M.waiting_jobs[bufft] = nil
end

return M
