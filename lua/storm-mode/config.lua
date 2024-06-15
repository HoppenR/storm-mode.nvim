---@class storm-mode.config.mod: storm-mode.config
local M = {}

---@class storm-mode.config: table
---@field root? string
---@field compiler? string
local options

---@param opts? storm-mode.config
function M.setup(opts)
    if type(opts) ~= 'table' or type(opts.root) ~= 'string' or type(opts.compiler) ~= 'string' then
        local errmsg = "storm-mode: required keys: 'root' and 'compiler' not supplied"
        vim.notify(errmsg, vim.log.levels.ERROR)
        return
    end

    ---@type storm-mode.config
    options = vim.tbl_deep_extend('force', options or {}, opts or {})

    vim.api.nvim_create_user_command('StormClose', require('storm-mode.buffer').unset_mode, {})
    vim.api.nvim_create_user_command('StormDebugReColor', require('storm-mode.buffer').recolor, {})
    vim.api.nvim_create_user_command('StormMode', require('storm-mode.buffer').set_mode, {})
    vim.api.nvim_create_user_command('StormQuit', require('storm-mode.buffer').quit, {})
end

return setmetatable(M, {
    __index = function(_, key)
        return options[key]
    end,
})
