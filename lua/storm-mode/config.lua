---@class storm-mode.config.mod: storm-mode.config
local M = {}

---@class storm-mode.config
---@field compiler string
---@field highlights storm-mode.config.highlights
---@field root string
---@field include storm-mode.config.include[]
---@field diagnostics boolean
---@field indent_width integer|false

---@class storm-mode.config.include
---@field path string directory containing the package
---@field public package string name of the package, e.g. "mylib" or "my.lib"

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
    include = {},
    diagnostics = true,
    indent_width = 4,
}

---@type storm-mode.config?
local options

---@param opts? storm-mode.setupOpts
function M.configure(opts)
    if opts == nil then return end
    vim.validate('compiler', opts.compiler, 'string', true)
    vim.validate('highlights', opts.highlights, 'table', true)
    vim.validate('root', opts.root, 'string', true)
    vim.validate('include', opts.include, 'table', true)
    vim.validate('diagnostics', opts.diagnostics, 'boolean', true)
    vim.validate(
        'indent_width',
        opts.indent_width,
        function(v) return v == nil or v == false or (type(v) == 'number' and v > 0 and v % 1 == 0) end,
        'a positive integer or false'
    )
    if opts.highlights ~= nil then
        for _, key in ipairs({
            'comment',
            'delimiter',
            'string',
            'constant',
            'keyword',
            'fn-name',
            'var-name',
            'type-name',
        }) do
            vim.validate('highlights.' .. key, opts.highlights[key], 'string', true)
        end
    end
    for i, inc in ipairs(opts.include or {}) do
        vim.validate('include[' .. i .. '].path', inc.path, 'string')
        vim.validate('include[' .. i .. '].package', inc.package, 'string')
    end
    -- Later calls (e.g. from a project's .nvim.lua) change only the given options.
    -- Lists are replaced, not merged
    local current = options or default_options
    options = vim.tbl_deep_extend('force', current, opts)
    options.include = opts.include or current.include
end

return setmetatable(M, {
    __index = function(_, key)
        if options == nil then return default_options[key] end
        return options[key]
    end,
})
