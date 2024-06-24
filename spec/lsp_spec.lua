---@module "busted"
local Lsp = require('storm-mode.lsp')
local Log = require('storm-mode.log')

local function wait_for_log_output()
    vim.g.waiting_for_log = false
    vim.api.nvim_create_autocmd('TextChanged', {
        once = true,
        buffer = Log._bufnr,
        callback = function() vim.g.waiting_for_log = true end,
    })
    vim.wait(500, function() return vim.g.waiting_for_log end, 10)
    vim.g.waiting_for_log = false
end

describe('lsp', function()
    before_each(function()
        Log.clear()
    end)

    local expected_small_tree = {
        'Range: (0 - 61)',
        'Int addTwoNumbers(Int lhs, Int rhs) {',
        '    return lhs + rhs;',
        '}',
    }

    it('debug log contents', function()
        vim.cmd.edit('spec/test_data/small_source.bs')
        vim.cmd.Storm('start')
        wait_for_log_output()

        assert.True(Lsp.is_running())

        vim.cmd.Storm({ 'debug', 'tree' })
        wait_for_log_output()
        local log_lines = Log.get()

        assert.are.equal('Language server started.', log_lines[1])
        local actual_small_tree = vim.list_slice(log_lines, 8, 11)
        assert.are.same(expected_small_tree, actual_small_tree)

        vim.cmd.Storm('quit')
    end)
end)
