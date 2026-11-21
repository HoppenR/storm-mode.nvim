local M = {}

local Output = require('storm-mode.output')

---@alias storm-mode.handlers.callback fun(reply: storm-mode.sexp[]?, err: string?)

---Callbacks waiting for a reply, per reply header. Storm answers requests of
---one kind in the order they were sent, so each queue is FIFO.
---@type table<string, storm-mode.handlers.callback[]>
M.pending = {}

---Wait for the next message with `header`
---@param header string
---@param callback storm-mode.handlers.callback called with the message minus its header
function M.expect(header, callback)
    local queue = M.pending[header]
    if queue == nil then
        queue = {}
        M.pending[header] = queue
    end
    table.insert(queue, callback)
end

---Fail all pending requests, e.g. because Storm exited
---@param reason string
function M.reset(reason)
    local pending = M.pending
    M.pending = {}
    for _, queue in pairs(pending) do
        for _, callback in ipairs(queue) do
            local ok, err = pcall(callback, nil, reason)
            if not ok then Output.notify('error in request callback: ' .. tostring(err), vim.log.levels.ERROR) end
        end
    end
end

---Handle sym 'color' message: (color id edit start [length color]...)
---@param args storm-mode.sexp[]
local function on_color(args)
    local sbufnr = args[1] --[[@as integer]]
    local edit_id = args[2] --[[@as integer]]
    local start = args[3] --[[@as integer]]
    ---@type [integer, storm-mode.sym|vim.NIL][]
    local colors = {}
    for i = 4, #args - 1, 2 do
        table.insert(colors, { args[i], args[i + 1] })
    end
    require('storm-mode.buffer').apply_colors(sbufnr, colors, edit_id, start)
end

---Messages that arrive without a pending request
---@type table<string, fun(args: storm-mode.sexp[])>
local unsolicited = { color = on_color }

---Forward the message to the waiting request or the relevant handler
---@param message storm-mode.sexp[]
function M.resolve(message)
    local header = tostring(message[1])
    local args = vim.list_slice(message, 2)

    local queue = M.pending[header]
    if queue ~= nil and #queue > 0 then
        local callback = table.remove(queue, 1)
        callback(args)
        return
    end

    local handler = unsolicited[header]
    if handler ~= nil then
        handler(args)
        return
    end
    Output.notify('unhandled message: ' .. header, vim.log.levels.WARN)
end

return M
