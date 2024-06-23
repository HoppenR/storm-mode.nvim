---@class storm-mode.config.mod: storm-mode.config
local M = {}

---@class storm-mode.config
---@field compiler? string
---@field highlights storm-mode.config.highlights
---@field root? string

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

---@type storm-mode.config?
local options

---@param args? storm-mode.setupArgs
function M.setup(args)
    assert(args, 'storm-mode: expected args to not be nil')
    vim.validate({
        compiler = { args.compiler, 'string' },
        highlights = { args.highlights, 'table', true },
        root = { args.root, 'string' },
    })

    options = vim.tbl_deep_extend('force', default_options, args)
    vim.validate({
        { options.highlights['comment'],   'string' },
        { options.highlights['delimiter'], 'string' },
        { options.highlights['string'],    'string' },
        { options.highlights['constant'],  'string' },
        { options.highlights['keyword'],   'string' },
        { options.highlights['fn-name'],   'string' },
        { options.highlights['var-name'],  'string' },
        { options.highlights['type-name'], 'string' },
    })
end

return setmetatable(M, {
    __index = function(_, key)
        return options ~= nil and options[key] or nil
    end,
})
