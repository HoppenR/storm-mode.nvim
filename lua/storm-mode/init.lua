local M = {}

---Entry point. Set up starting storm-mode
---@param opts? storm-mode.config
function M.setup(opts)
    require('storm-mode.config').setup(opts)
end

-- TODO(Hop): Add more events, add more filetypes
--       can ask the LSP which filetype is good

-- TODO(Hop): Add tests for utility function and actual lsp communication

-- TODO(Hop): Implement handlers for more LSP message types

-- TODO(Hop): Keep track of edit points
--            buffer.lua: { storm_buffer_last_point, cursor_position }
--            Then send buffer changes

return M
