---@class storm-mode.config.mod: storm-mode.config
local M = {}

---@class storm-mode.config: table
---@field root? string
---@field compiler? string
local options = {}

---@param opts? storm-mode.config
function M.setup(opts)
    if type(opts) ~= 'table' or type(opts.root) ~= 'string' or type(opts.compiler) ~= 'string' then
        local errmsg = "storm-mode: required keys: 'root' and 'compiler' not supplied"
        vim.notify(errmsg, vim.log.levels.ERROR)
        return
    end

    for k, v in pairs(opts) do
        options[k] = v
    end

    require('storm-mode.buffer').setup()
end

return setmetatable(M, {
    __index = options,
})
