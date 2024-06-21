local M = {}

---@type table<string, function<nil>>
local subcommands = {
    close = function() require('storm-mode.buffer').manual_unset_mode() end,
    global = function() require('storm-mode.buffer').global_set_mode() end,
    quit = function() require('storm-mode.buffer').quit() end,
    recolor = function() require('storm-mode.buffer').recolor() end,
    start = function() require('storm-mode.buffer').manual_set_mode() end,
}

function M.handle_command(args)
    local cmd = subcommands[args.fargs[1]]
    if cmd ~= nil then
        cmd()
    end
end

function M.setup()
    vim.api.nvim_create_user_command('Storm', M.handle_command, {
        nargs = "+",
        complete = function(arg_lead, _, _)
            local keys = vim.tbl_keys(subcommands)
            local predicate = function(key) return key:find(arg_lead) ~= nil end
            return vim.iter(keys):filter(predicate):totable()
        end
    })
end

return M
