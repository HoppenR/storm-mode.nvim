---@class storm-mode.config.mod: storm-mode.config
local M = {}

---@class storm-mode.config
---@field root? string
---@field compiler? string
---@field highlights? storm-mode.config.highlights

---@class storm-mode.config.highlights
---@field comment string
---@field delimiter string
---@field string string
---@field constant string
---@field keyword string
---@field fn-name string
---@field var-name string
---@field type-name string

---@type storm-mode.config
local default_options = {
    compiler = nil,
    root = nil,
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

---@type storm-mode.config
local options = {}

---@param opts? storm-mode.config
function M.setup(opts)
    opts = vim.tbl_deep_extend('force', default_options, opts)

    for k, v in pairs(opts) do
        options[k] = v
    end

    vim.validate({
        compiler = { options.compiler, 'string' },
        root = { options.root, 'string' },
        highlights = { options.highlights, 'table' },
    })
end

return setmetatable(M, {
    __index = options,
})
