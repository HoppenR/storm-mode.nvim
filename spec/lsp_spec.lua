---@diagnostic disable: undefined-global
local Handlers = require('storm-mode.handlers')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal
---Wait for spy to be called once, timing out after 500ms
local function wait_called(modspy)
    local ok, _ = vim.wait(500, function() return #modspy.calls > 0 end, 20)
    return ok
end

describe('lsp', function()
    local handlers_resolve_spy, lsp_stdout_spy, lsp_exit_spy
    local bufnr

    setup(function()
        handlers_resolve_spy = spy.on(Handlers, 'resolve')
        lsp_stdout_spy = spy.on(Lsp, '_on_stdout')
        lsp_exit_spy = spy.on(Lsp, '_on_exit')
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()

        vim.cmd.Storm('start')
        assert.True(wait_called(lsp_stdout_spy))
        assert.spy(lsp_stdout_spy).was_called_with(nil, 'Language server started.\n')

        assert.True(wait_called(handlers_resolve_spy))
        assert.spy(handlers_resolve_spy).was_called_with(match.is_messagetype(sym 'color'))
    end)

    teardown(function()
        vim.cmd.Storm('quit')
        assert.True(wait_called(lsp_exit_spy))
        assert.spy(lsp_exit_spy).was_called_with(match._, 0)

        vim.api.nvim_buf_delete(bufnr, { force = true })
        handlers_resolve_spy:revert()
        lsp_stdout_spy:revert()
        lsp_exit_spy:revert()
    end)
end)
