local M = {}

local Commands = require('storm-mode.commands')

-- TODO(Hop): Parse :Storm debug error location and jump to it?
-- TODO(Hop): Remove very old bufstates, keep the 20-30 last ones
-- TODO(Hop): Download latest storm release for testing

-- TODO(Hop): ('indent) Implement handler
-- TODO(Hop): Create a helper Config.notify function to easily apply args
--            like { group = 'Storm' },
--            can also be used to configure what notifier to us
-- TODO(Hop): Set up an output window to simulate emacs' *compilation* buffer

---@class storm-mode.setupArgs
---@field compiler string
---@field highlights? storm-mode.setupArgs.highlights
---@field root string

---@class storm-mode.setupArgs.highlights
---@field comment? string
---@field delimiter? string
---@field string? string
---@field constant? string
---@field keyword? string
---@field fn-name? string
---@field var-name? string
---@field type-name? string

---Configure storm-mode
---@param args? storm-mode.setupArgs
function M.setup(args)
    local Config = require('storm-mode.config')
    Config.setup(args)
end

-- Make the lazy commands available before the plugin is initialized,
-- this may leave configuration options in a bad state.
-- To troubleshoot, use `:checkhealth storm-mode`.
Commands.setup()

return M
