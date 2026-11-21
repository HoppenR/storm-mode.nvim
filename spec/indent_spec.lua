---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
local Lsp = require('storm-mode.lsp')

describe('indentation', function()
    local bufnr

    before_each(function()
        vim.cmd.edit('spec/test_data/indent.bs')
        bufnr = vim.api.nvim_get_current_buf()
        vim.bo[bufnr].shiftwidth = 4
        vim.bo[bufnr].expandtab = true
        vim.cmd.Storm('start')
    end)

    after_each(function()
        vim.cmd.Storm('quit')
        vim.wait(3000, function() return not Lsp.is_running() end)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('gg=G indents as Storm says', function()
        vim.cmd('silent normal! gg=G')
        assert.are.same({
            'Int addTwoNumbers(Int lhs, Int rhs) {',
            '    return lhs + rhs;',
            '}',
            '',
            'void loop() {',
            '    for (Int i = 0; i < 10; i++) {',
            '        print(i.toS);',
            '    }',
            '    Str s = "a" +',
            '    "b";',
            '}',
        }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('indents new lines and re-indents a typed }', function()
        vim.cmd('silent normal! gg=G')
        -- Open a line inside the for loop and close a new block
        vim.api.nvim_feedkeys(vim.keycode('7Goif (i == 2) {<CR>break;<CR>}<Esc>'), 'tx', false)
        assert.are.same({
            '        print(i.toS);',
            '        if (i == 2) {',
            '            break;',
            '        }',
            '    }',
        }, vim.api.nvim_buf_get_lines(bufnr, 6, 11, false))
    end)

    it('indents to the column of a character when Storm answers `as`', function()
        local sym = require('storm-mode.sym').literal
        local id = require('storm-mode.buffer').storm_id(bufnr)
        -- Line 9 is `Str s = "a" +`: indent line 10 as the `"` of "a" (char offset
        -- of line 9's start + 8). Storm 0.8.2 only answers with levels.
        local line9 = vim.api.nvim_buf_get_offset(bufnr, 8)
        local request_stub = stub(Lsp, 'request_sync').returns({ id, sym 'as', line9 + 8 })
        vim.cmd('silent normal! 10G==')
        request_stub:revert()
        assert.are.equal('        "b";', vim.api.nvim_buf_get_lines(bufnr, 9, 10, false)[1])
    end)

    it('keeps the indentation when Storm does not answer', function()
        local request_stub = stub(Lsp, 'request_sync').returns(nil, 'timeout')
        vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { '  return lhs + rhs;' })
        vim.cmd('silent normal! 2G==')
        request_stub:revert()
        assert.are.equal('  return lhs + rhs;', vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1])
    end)
end)
