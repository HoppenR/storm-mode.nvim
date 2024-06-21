local M = {}

---Entry point. Set up starting storm-mode
---@param opts? storm-mode.config
function M.setup(opts)
    require('storm-mode.config').setup(opts)
end

-- TODO(Hop): Keep track of edit points
--            buffer.lua: { storm_buffer_last_point, cursor_position }
--            Then send buffer changes ('edit)

-- TODO(Hop): ('color, 'debug(2)): Interpret empty entries in a message as `nil`
--                                 This requires iterating 1..message[-1][1]

-- TODO(Hop): ('edit / util.lua): Add tests

-- TODO(Hop): Make :Storm* into a single command with sub-commands, i.e
--            :Storm start
--            :Storm global
--            :Storm close
--            :Storm quit

return M
