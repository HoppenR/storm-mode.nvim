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
---@field impl fun(args: string[], rest: string, bang: boolean) `rest` is the unsplit text after the
---subcommand, `bang` whether it ended in ! (`:Storm restart!`)
---@field complete? fun(subcmd_arg_lead: string, arg_lead: string): string[]
---@field buffer? boolean acts on the current buffer, which must be in storm-mode

---@param words string[]
---@return fun(lead: string): string[]
local function complete_words(words)
    return function(lead)
        return vim.tbl_filter(function(w) return vim.startswith(w, lead) end, words)
    end
end

local function buffer() return require('storm-mode.buffer') end
local function interactive() return require('storm-mode.interactive') end

---@type table<string, storm-mode.commands.item>
local debug_subcommands = {
    content = { impl = function() buffer().debug_content() end },
    error = { impl = function() buffer().debug_error() end },
    recolor = { impl = function() buffer().debug_recolor() end },
    reopen = { impl = function() buffer().debug_reopen() end },
    tree = { impl = function() buffer().debug_tree() end },
    uncolor = { impl = function() buffer().debug_uncolor() end },
}

---@type table<string, storm-mode.commands.item>
local subcommand_tbl = {
    close = { buffer = true, impl = function() buffer().manual_unset_mode() end },
    global = {
        impl = function(args)
            local action = args[1] or 'enable'
            if action ~= 'enable' and action ~= 'disable' and action ~= 'toggle' then
                vim.notify('Storm: usage: :Storm global [enable|disable|toggle]', vim.log.levels.ERROR)
                return
            end
            buffer().global_set_mode(action)
        end,
        complete = complete_words({ 'enable', 'disable', 'toggle' }),
    },
    quit = { impl = function() buffer().quit() end },
    restart = {
        impl = function(_, _, bang)
            -- Storm loads code from disk when it starts: save it first
            if bang then interactive().write_buffers(function() return true end) end
            require('storm-mode.lsp').restart()
        end,
    },
    start = { impl = function() buffer().manual_set_mode() end },
    doc = {
        buffer = true,
        impl = function(_, rest)
            local name = vim.trim(rest)
            if name == '' then name = require('storm-mode.complete').name_at_cursor() or '' end
            if name == '' then
                vim.notify('Storm: no name given and none under the cursor', vim.log.levels.ERROR)
                return
            end
            require('storm-mode.doc').show(name)
        end,
        complete = function(subcmd_arg_lead, arg_lead)
            -- Completing asks Storm: don't start it for a buffer outside storm-mode
            if require('storm-mode.buffer').storm_id(vim.api.nvim_get_current_buf()) == nil then return {} end
            return require('storm-mode.complete').complete_cmdline(arg_lead, subcmd_arg_lead)
        end,
    },
    eval = { buffer = true, impl = function(_, rest) interactive().eval(vim.trim(rest)) end },
    run = {
        buffer = true,
        impl = function(args)
            if args[1] ~= nil and args[1] ~= 'cursor' then
                vim.notify('Storm: usage: :Storm run [cursor]', vim.log.levels.ERROR)
                return
            end
            interactive().run(args[1] == 'cursor')
        end,
        complete = complete_words({ 'cursor' }),
    },
    reload = {
        buffer = true,
        impl = function(args)
            if args[1] == nil then
                interactive().reload_buffer()
            elseif args[1] == 'package' and #args == 1 then
                interactive().reload_package()
            else
                interactive().reload_files(args)
            end
        end,
        complete = function(lead)
            local files = vim.fn.getcompletion(lead:match('%S*$'), 'file')
            if not lead:find('%s') then table.insert(files, 1, 'package') end
            return vim.tbl_filter(function(w) return vim.startswith(w, lead:match('%S*$')) end, files)
        end,
    },
    errors = { buffer = true, impl = function() require('storm-mode.errors').show() end },
    debug = {
        buffer = true,
        impl = function(args)
            if args == nil or args[1] == nil then return end
            local subcommand_key = args[1]
            local subcommand = debug_subcommands[subcommand_key]
            if not subcommand then
                vim.notify('Storm: Unknown debug command: ' .. subcommand_key, vim.log.levels.ERROR)
                return
            end
            subcommand.impl({}, '', false)
        end,
        complete = function(subcmd_arg_lead)
            return vim.tbl_filter(
                function(key) return key:find(subcmd_arg_lead, 1, true) ~= nil end,
                vim.tbl_keys(debug_subcommands)
            )
        end,
    },
}

---@param opts vim.UsercmdOpts
function M._handle_command(opts)
    local subcommand_key, bang = opts.fargs[1]:match('^(.-)(!?)$')
    local args = #opts.fargs > 1 and vim.list_slice(opts.fargs, 2, #opts.fargs) or {}
    local rest = opts.args:match('^%s*%S+%s+(.-)%s*$') or ''
    local subcommand = subcommand_tbl[subcommand_key]
    if not subcommand then
        vim.notify('Storm: Unknown command: ' .. opts.fargs[1], vim.log.levels.ERROR)
        return
    end
    if subcommand.buffer and not buffer().require_mode() then return end
    subcommand.impl(args, rest, bang == '!')
end

---@param arg_lead string
---@param cmdline string
---@param _ integer
---@return string[]
function M._complete_command(arg_lead, cmdline, _)
    local subcmd_key, subcmd_arg_lead = cmdline:match('^%S*Storm%s+(%S+)%s+(.*)$')
    if subcmd_key and subcmd_arg_lead and subcommand_tbl[subcmd_key] and subcommand_tbl[subcmd_key].complete then
        return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead, arg_lead)
    end

    if cmdline:match('^%S*Storm%s+%w*$') then
        local keys = vim.tbl_filter(
            function(key) return key:find(arg_lead, 1, true) ~= nil end,
            vim.tbl_keys(subcommand_tbl)
        )
        table.sort(keys)
        return keys
    end
    return {}
end

vim.api.nvim_create_user_command('Storm', M._handle_command, {
    nargs = '+',
    complete = M._complete_command,
})

---<Plug> mappings, see :help storm-mode.mappings
local function plug(modes, name, rhs, desc)
    vim.keymap.set(modes, '<Plug>(' .. name .. ')', rhs, { desc = 'Storm: ' .. desc })
end
plug(
    'n',
    'storm-doc-hover',
    function() require('storm-mode.doc').hover() end,
    'documentation for the name under the cursor (floating window)'
)
plug('n', 'storm-doc', '<Cmd>Storm doc<CR>', 'documentation for the name under the cursor (split)')
plug('n', 'storm-eval', '<Cmd>Storm eval<CR>', 'evaluate an expression')
plug('x', 'storm-eval', function()
    if not buffer().require_mode() then return end
    local lines = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
    vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
    interactive().eval(table.concat(lines, '\n'))
end, 'evaluate the selection')
plug('n', 'storm-run-cursor', '<Cmd>Storm run cursor<CR>', 'run the function at the cursor')
plug('n', 'storm-run-all', '<Cmd>Storm run<CR>', 'run all functions in the file')
plug('n', 'storm-reload', '<Cmd>Storm reload<CR>', 'reload the buffer')
plug('n', 'storm-reload-package', '<Cmd>Storm reload package<CR>', 'reload the package')
plug('n', 'storm-errors', '<Cmd>Storm errors<CR>', 'Storm errors in the quickfix list')
plug('n', 'storm-start', '<Cmd>Storm start<CR>', 'start storm-mode for the buffer')
plug('n', 'storm-restart', '<Cmd>Storm restart<CR>', 'restart Storm')
for _, name in ipairs({ 'content', 'error', 'recolor', 'reopen', 'tree', 'uncolor' }) do
    plug('n', 'storm-debug-' .. name, '<Cmd>Storm debug ' .. name .. '<CR>', 'debug ' .. name)
end

return M
