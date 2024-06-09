local M = {}

---Entry point. Set up starting storm_mode
---@param opts? storm-mode.Config
function M.setup(opts)
    require('storm-mode.config').setup(opts)
end

-- TODO: Add more events, add more filetypes
--       can ask the LSP which filetype is good

-- TODO(Hop): handle waiting for LSP to start up (needs a few ms)
-- TODO(Hop): Keep track of edit points
--            buffer.lua: { storm_buffer_last_point, cursor_position }
-- TODO(Hop): Handle color data
-- TODO(Hop): Create tests?
-- TODO(Hop): Fix decoding

return M
