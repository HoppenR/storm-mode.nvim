---@class storm-mode.Config.mod: storm-mode.Config
local M = {}

local Buffer = require('storm-mode.buffer')

---@class storm-mode.Config
---@field root string
---@field compiler string
local options

---@param opts? storm-mode.Config
---@return storm-mode.Config?
function M.setup(opts)
    if type(opts) ~= 'table' or type(opts.root) ~= 'string' or type(opts.compiler) ~= 'string' then
        local errmsg = "storm-mode: required keys: 'root' and 'compiler' not supplied"
        vim.notify(errmsg, vim.log.levels.ERROR)
        return nil
    end

    ---@type storm-mode.Config
    options = vim.tbl_deep_extend('force', options or {}, opts or {})

    local StormMode = vim.api.nvim_create_augroup(
        'StormMode',
        { clear = true }
    )
    vim.api.nvim_create_autocmd(
        'BufRead',
        {
            pattern = '*.bs',
            group = StormMode,
            callback = Buffer.storm_mode,
        }
    )
    return options
end

return setmetatable(M, {
    __index = function(_, key)
        return options[key]
    end,
})
