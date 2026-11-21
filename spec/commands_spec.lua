---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- :Storm commands, without Storm (stubbed out)
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')

describe(':Storm', function()
    local lsp_send_stub, lsp_start_stub
    local bufnr

    setup(function()
        lsp_send_stub = stub.new(Lsp, 'send')
        -- set_mode and flush start Storm; these tests don't use a real one
        lsp_start_stub = stub.new(Lsp, 'start')
    end)

    teardown(function()
        lsp_send_stub:revert()
        lsp_start_stub:revert()
    end)

    before_each(function()
        lsp_send_stub:clear()
        lsp_start_stub:clear()
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()
    end)

    after_each(function() vim.api.nvim_buf_delete(bufnr, { force = true }) end)

    it(':Storm global enables, disables and toggles global storm-mode', function()
        local function autocmds() return #vim.api.nvim_get_autocmds({ group = 'StormModeGlobal' }) end
        local out = StormTest.record()
        vim.cmd.Storm({ 'global' })
        vim.cmd.Storm({ 'global', 'enable' })
        assert.is_true(Buffer.global_enabled)
        assert.are.equal(2, autocmds(), 'BufRead and BufNewFile, once')
        vim.cmd.Storm({ 'global', 'disable' })
        assert.is_false(Buffer.global_enabled)
        assert.are.equal(0, autocmds())
        vim.cmd.Storm({ 'global', 'toggle' })
        assert.is_true(Buffer.global_enabled)
        vim.cmd.Storm({ 'global', 'toggle' })
        out.restore()
        assert.is_false(Buffer.global_enabled)
        assert.are.equal(0, autocmds())
        assert.are.same(
            { 'Storm: global storm-mode is on', 'Storm: global storm-mode is off' },
            vim.tbl_map(function(n) return n.msg end, out.notifications)
        )
    end)

    it('commands that act on a buffer require storm-mode and do not start Storm', function()
        local out = StormTest.record()
        local commands = {
            { 'doc', 'core.Str' },
            { 'eval', '1 + 2' },
            { 'run' },
            { 'run', 'cursor' },
            { 'reload' },
            { 'reload', 'package' },
            { 'reload', '%' },
            { 'errors' },
            { 'close' },
            { 'debug', 'tree' },
            { 'debug', 'content' },
            { 'debug', 'error' },
            { 'debug', 'recolor' },
            { 'debug', 'reopen' },
            { 'debug', 'uncolor' },
        }
        for _, command in ipairs(commands) do
            vim.cmd.Storm(command)
        end
        -- Mappings that don't go through :Storm
        require('storm-mode.doc').hover()
        vim.keymap.set('x', '<F5>', '<Plug>(storm-eval)', { buffer = bufnr })
        vim.api.nvim_feedkeys(vim.keycode('ggv$<F5>'), 'x', false)
        -- Completing names would ask Storm
        local completions = require('storm-mode.commands')._complete_command('core.St', 'Storm doc core.St', 0)
        out.restore()

        assert.are.same({}, completions)
        assert.stub(lsp_start_stub).was_not_called()
        assert.stub(lsp_send_stub).was_not_called()
        local warnings = vim.tbl_filter(
            function(n) return n.msg == 'Storm: the buffer is not in storm-mode, see :Storm start' end,
            out.notifications
        )
        assert.are.equal(#commands + 2, #warnings)
    end)
end)
