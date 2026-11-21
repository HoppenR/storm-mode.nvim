---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
local Complete = require('storm-mode.complete')
local Lsp = require('storm-mode.lsp')

describe('name completion', function()
    local bufnr

    setup(function()
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()
        vim.cmd.Storm('start')
    end)

    teardown(function()
        vim.cmd.Storm('quit')
        vim.wait(3000, function() return not Lsp.is_running() end)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('asks Storm for names', function()
        local names = Complete.names('core.St')
        assert.is_true(vim.tbl_contains(names, 'core.Str'))
        assert.is_true(vim.tbl_contains(names, 'core.StrBuf'))
    end)

    it('omnifunc finds the start of a dotted name and returns items', function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'x = core.St' })
        vim.api.nvim_win_set_cursor(0, { 1, #'x = core.St' })
        assert.are.equal(#'x = ', Complete.omnifunc(1, ''))
        local words = vim.tbl_map(function(item) return item.word end, Complete.omnifunc(0, 'core.St'))
        assert.is_true(vim.tbl_contains(words, 'core.Str'))
    end)

    it('groups overloads into one item', function()
        local items = Complete.items('')
        local clamp = vim.tbl_filter(function(item) return item.word == 'clamp' end, items)
        assert.are.equal(1, #clamp)
        assert.are.equal('clamp(…)', clamp[1].abbr)
        assert.matches('clamp%(core%.Int, core%.Int, core%.Int%)', clamp[1].info)
    end)

    it('<C-x><C-o> completes in a storm-mode buffer', function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '' })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        -- A single match is inserted right away
        vim.api.nvim_feedkeys(vim.keycode('icore.StrB<C-x><C-o><Esc>'), 'tx', false)
        assert.are.equal('core.StrBuf', vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
        vim.cmd('silent! undo')
    end)

    it('completes :Storm doc names, keeping text before the last word', function()
        assert.is_true(vim.tbl_contains(Complete.complete_cmdline('core.St', 'core.St'), 'core.Str'))
        -- Typed "clamp(core.Int, co": only the text after the last space is replaced
        local names = Complete.complete_cmdline('core.Int, core.Int)', 'clamp(core.Int, core.Int, core.Int)')
        assert.are.same({ 'core.Int, core.Int)' }, names)
    end)

    it('finds the name under the cursor including dots', function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo(core.Str.size);' })
        vim.api.nvim_win_set_cursor(0, { 1, 9 })
        assert.are.equal('core.Str.size', Complete.name_at_cursor())
        vim.api.nvim_win_set_cursor(0, { 1, 3 })
        assert.is_nil(Complete.name_at_cursor())
        vim.cmd('silent! undo')
    end)
end)
