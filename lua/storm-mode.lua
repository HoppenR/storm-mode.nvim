local M = {}

---@class storm-mode.setupOpts
---@field compiler? string
---@field highlights? storm-mode.setupOpts.highlights
---@field root? string
---@field include? storm-mode.config.include[] packages outside the root, passed as `-I package path`
---@field diagnostics? boolean check buffers for syntax errors after changes (default true)
---@field indent_width? integer|false 'tabstop' and 'shiftwidth' in storm-mode buffers (default 4)

---@class storm-mode.setupOpts.highlights
---@field comment? string
---@field delimiter? string
---@field string? string
---@field constant? string
---@field keyword? string
---@field fn-name? string
---@field var-name? string
---@field type-name? string

---Configure storm-mode
---@param opts? storm-mode.setupOpts
function M.setup(opts)
    local Config = require('storm-mode.config')
    Config.configure(opts)
end

-- Make the lazy commands available before the plugin is initialized
require('storm-mode.commands')

return M
