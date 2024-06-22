local M = {}

local Commands = require('storm-mode.commands')
local Config = require('storm-mode.config')

-- TODO(Hop): Parse :Storm debug error location and jump to it?

-- TODO(Hop): Create doc/
-- TODO(Hop): Set up an output window to simulate emacs' *compilation* buffer
-- TODO(Hop): Download latest storm release for testing??

---Configure storm-mode
---@param opts? storm-mode.config
function M.setup(opts)
    Config.setup(opts)
end

-- Make the lazy commands available before the plugin is initialized
-- this may leave configuration options in a bad state, to troubleshoot use
-- `:checkhealth storm-mode`
Commands.setup()

return M
