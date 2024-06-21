---@class storm-mode.config.mod: storm-mode.config
local M = {}

---@class storm-mode.config.highlights
---@field comment string
---@field delimiter string
---@field string string
---@field constant string
---@field keyword string
---@field fn-name string
---@field var-name string
---@field type-name string

---@class storm-mode.config: table
---@field root? string
---@field compiler? string
---@field highlights storm-mode.config.highlights
local default_options = {
    highlights = {
        ['comment'] = 'Comment',
        ['delimiter'] = 'Delimiter',
        ['string'] = 'String',
        ['constant'] = 'Constant',
        ['keyword'] = 'Keyword',
        ['fn-name'] = 'Function',
        ['var-name'] = 'Identifier',
        ['type-name'] = 'Type',
    },
}

---@param opts? storm-mode.config
function M.setup(opts)
    if type(opts) ~= 'table' or type(opts.root) ~= 'string' or type(opts.compiler) ~= 'string' then
        local errmsg = "storm-mode: required keys: 'root' and 'compiler' not supplied"
        vim.notify(errmsg, vim.log.levels.ERROR)
        return
    end

    M.options = vim.tbl_deep_extend('force', default_options, opts)

    require('storm-mode.buffer').setup()
end

return setmetatable(M, {
    __index = function(_, key)
        return M.options[key]
    end,
})
