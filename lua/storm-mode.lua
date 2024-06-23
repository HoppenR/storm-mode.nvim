local M = {}

-- TODO(Hop): Parse :Storm debug error location and jump to it?
-- TODO(Hop): Remove very old bufstates, keep the 20-30 last ones

-- TODO(Hop): ('indent) Implement handler
-- TODO(Hop): Create a helper Config.notify function to easily apply args
--            like { group = 'Storm' },
--            can also be used to configure what notifier to us
-- TODO(Hop): Set up an output window to simulate emacs' *compilation* buffer

---@class storm-mode.setupOpts
---@field compiler? string
---@field highlights? storm-mode.setupOpts.highlights
---@field root? string

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
