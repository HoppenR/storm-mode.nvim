local M = {}

---Entry point. Set up starting storm-mode
---@param opts? storm-mode.config
function M.setup(opts)
    require('storm-mode.config').setup(opts)
end

-- TODO(Hop): Keep track of edit points
--            buffer.lua: { storm_buffer_last_point, cursor_position }
--            Then send buffer changes ('edit)

-- TODO(Hop): ('edit / 'debug(2)):  Add tests with vim.NIL in messages


return M
