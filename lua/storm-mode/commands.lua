local M = {}

---@class vim.UsercmdOpts
---@field args string
---@field bang boolean
---@field count integer
---@field fargs string[]
---@field line1 integer
---@field line2 integer
---@field mods string
---@field name string
---@field range integer
---@field reg string
---@field smods table

---@class storm-mode.commands.item
---@field impl fun(args: string[] | nil)
---@field complete? fun(subcmd_arg_lead: string): string[]

---@type table<string, storm-mode.commands.item>
local debug_subcommands = {
    content = { impl = function() require('storm-mode.buffer').debug_content() end },
    error = { impl = function() require('storm-mode.buffer').debug_error() end },
    recolor = { impl = function() require('storm-mode.buffer').debug_recolor() end },
    tree = { impl = function() require('storm-mode.buffer').debug_tree() end },
}

---@type table<string, storm-mode.commands.item>
local subcommand_tbl = {
    close = { impl = function() require('storm-mode.buffer').manual_unset_mode() end },
    global = { impl = function() require('storm-mode.buffer').global_set_mode() end },
    quit = { impl = function() require('storm-mode.buffer').quit() end },
    start = { impl = function() require('storm-mode.buffer').manual_set_mode() end },
    debug = {
        impl = function(args)
            if args == nil or args[1] == nil then return end
            local subcommand_key = args[1]
            local subcommand = debug_subcommands[subcommand_key]
            if not subcommand then
                vim.notify("Storm: Unknown debug command: " .. subcommand_key, vim.log.levels.ERROR)
                return
            end
            subcommand.impl()
        end,
        complete = function(subcmd_arg_lead)
            return vim.tbl_filter(function(key)
                return key:find(subcmd_arg_lead) ~= nil
            end, vim.tbl_keys(debug_subcommands))
        end,
    },
}

---@param opts vim.UsercmdOpts
local function handle_command(opts)
    local subcommand_key = opts.fargs[1]
    local args = #opts.fargs > 1 and vim.list_slice(opts.fargs, 2, #opts.fargs) or {}
    local subcommand = subcommand_tbl[subcommand_key]
    if not subcommand then
        vim.notify("Storm: Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
        return
    end
    subcommand.impl(args)
end

---@param arg_lead string
---@param cmdline string
---@param _ integer
---@return string[]
local function complete_command(arg_lead, cmdline, _)
    local subcmd_key, subcmd_arg_lead = cmdline:match("^Storm%s(%S+)%s(.*)$")
    if subcmd_key
        and subcmd_arg_lead
        and subcommand_tbl[subcmd_key]
        and subcommand_tbl[subcmd_key].complete
    then
        return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
    end

    if cmdline:match("^Storm%s+%w*$") then
        return vim.tbl_filter(function(key)
            return key:find(arg_lead) ~= nil
        end, vim.tbl_keys(subcommand_tbl))
    end
    return {}
end

function M.setup()
    vim.api.nvim_create_user_command('Storm', handle_command, {
        nargs = "+",
        complete = complete_command,
    })
end

return M
