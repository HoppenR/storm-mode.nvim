local M = {}

---Entry point. Set up starting storm-mode
---@param opts? storm-mode.config
function M.setup(opts)
    require('storm-mode.config').setup(opts)
end

-- TODO(Hop): ('supported): GlobalStormMode (autocommands)
--                          can ask the LSP which filetype is good

-- TODO(Hop): Keep track of edit points
--            buffer.lua: { storm_buffer_last_point, cursor_position }
--            Then send buffer changes ('edit)

-- TODO(Hop): Remake utils into a class for traversing UTF8 text
--           and getting (row, col)

-- TODO(Hop): ('color, 'debug(2)): Interpret empty entries in a message as `nil`
--                                 This requires iterating 1..message[-1][1]

-- TODO(Hop): Implement handlers for more LSP message types

return M
