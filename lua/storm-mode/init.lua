local M = {}

---Entry point. Set up starting storm-mode
---@param opts? storm-mode.config
function M.setup(opts)
    require('storm-mode.config').setup(opts)
end

-- TODO(Hop): Add more events, add more filetypes
--       can ask the LSP which filetype is good

-- TODO(Hop): Fix edge case where an entire message is left in the buffer
--       without being processed, right after another one is.

-- TODO(Hop): Keep track of edit points
--            buffer.lua: { storm_buffer_last_point, cursor_position }

-- TODO(Hop): Implement handlers for LSP message types (sym 'color', ...)

return M
