local M = {}

---Entry point. Set up starting storm-mode
---@param opts? storm-mode.config
function M.setup(opts)
    require('storm-mode.config').setup(opts)
end

-- TODO: Add more events, add more filetypes
--       can ask the LSP which filetype is good

-- TODO: Fix edge case where an entire message is left in the buffer
--       without being processed

-- TODO(Hop): Keep track of edit points
--            buffer.lua: { storm_buffer_last_point, cursor_position }
-- TODO(Hop): Fix handlers for LSP message types (sym 'color', ...)
-- TODO(Hop): handle waiting for LSP to start up

return M
