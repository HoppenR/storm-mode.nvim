---@class storm-mode.config.mod: storm-mode.config
local M = {}

---@class storm-mode.config
---@field compiler string
---@field highlights storm-mode.config.highlights
---@field root string

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
    compiler = '/usr/bin/storm',
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
    root = '/usr/lib/storm/',
}

---@type storm-mode.config?
local options

---@param opts? storm-mode.setupOpts
function M.configure(opts)
    if opts == nil then
        return
    end
    vim.validate({
        compiler = { opts.compiler, 'string', true },
        highlights = { opts.highlights, 'table', true },
        root = { opts.root, 'string', true },
    })
    if opts.highlights ~= nil then
        vim.validate({
            { opts.highlights['comment'],   'string', true },
            { opts.highlights['delimiter'], 'string', true },
            { opts.highlights['string'],    'string', true },
            { opts.highlights['constant'],  'string', true },
            { opts.highlights['keyword'],   'string', true },
            { opts.highlights['fn-name'],   'string', true },
            { opts.highlights['var-name'],  'string', true },
            { opts.highlights['type-name'], 'string', true },
        })
    end
    options = vim.tbl_deep_extend('force', default_options, opts)
end

return setmetatable(M, {
    __index = function(_, key)
        if options == nil then
            return default_options[key]
        end
        return options[key]
    end,
})
