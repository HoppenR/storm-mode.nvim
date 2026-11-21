---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Eval, run and reload against Storm, with spec/test_data/demo as package `demo`
local Errors = require('storm-mode.errors')
local Interactive = require('storm-mode.interactive')
local Lsp = require('storm-mode.lsp')

local MAIN = vim.fn.fnamemodify('spec/test_data/demo/main.bs', ':p')
local ANSWER_LINE = 6 -- `    40 + 2;`

local function wait(cond, ms) return vim.wait(ms or 5000, cond, 20) end

---All echoed lines (an echo can hold several lines of streamed output)
local function echoed_lines(out)
    local lines = {}
    for _, echo in ipairs(out.echoes) do
        vim.list_extend(lines, vim.split(echo.text, '\n', { plain = true }))
    end
    return lines
end

---Whether `expected` lines were echoed, in this order (output of earlier
---commands, e.g. a run that is still printing, may be echoed in between)
local function echoed_in_order(out, expected)
    local i = 1
    for _, line in ipairs(echoed_lines(out)) do
        if line == expected[i] then i = i + 1 end
    end
    return i > #expected
end

describe('interactive compilation', function()
    local bufnr, out

    local function compile_diagnostics(b) return vim.diagnostic.get(b or bufnr, { namespace = Errors.compile_ns }) end
    local function set_answer(text) vim.api.nvim_buf_set_lines(bufnr, ANSWER_LINE - 1, ANSWER_LINE, false, { text }) end

    setup(function()
        require('storm-mode').setup({
            compiler = os.getenv('STORM_COMPILER'),
            root = os.getenv('STORM_ROOT'),
            include = { { path = 'spec/test_data/demo', package = 'demo' } },
        })
        vim.cmd.edit(MAIN)
        bufnr = vim.api.nvim_get_current_buf()
        vim.cmd.Storm('start')
    end)

    teardown(function()
        vim.cmd.Storm('quit')
        wait(function() return not Lsp.is_running() end)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        require('storm-mode').setup({ compiler = os.getenv('STORM_COMPILER'), root = os.getenv('STORM_ROOT') })
    end)

    before_each(function()
        vim.cmd('silent! only')
        vim.api.nvim_set_current_buf(bufnr)
        vim.fn.setqflist({}, 'f') -- the quickfix list is global: start without one
        out = StormTest.record()
    end)

    after_each(function()
        out.restore()
        -- Restore the demo package
        if vim.api.nvim_buf_get_lines(bufnr, ANSWER_LINE - 1, ANSWER_LINE, false)[1] ~= '    40 + 2;' then
            set_answer('    40 + 2;')
            vim.cmd.Storm({ 'reload' })
            vim.wait(500)
        end
    end)

    it('passes include paths to Storm', function()
        local args = table.concat(Lsp.compiler_args(), ' ')
        assert.matches('%-I demo .*spec/test_data/demo/', args)
    end)

    it('lists REPLs', function() assert.are.same('bs', Interactive.repls()[1]) end)

    it(':Storm eval shows the result', function()
        vim.cmd.Storm({ 'eval', '1 + 2' })
        assert.is_true(out.wait_for('=> 3'))
        assert.is_true(echoed_in_order(out, { '=> 3' }))
    end)

    it(':Storm eval shows output printed by the expression before the result', function()
        vim.cmd.Storm({ 'eval', '{ print("from eval"); 2 + 2; }' })
        assert.is_true(out.wait_for('=> 4'))
        assert.is_true(echoed_in_order(out, { 'from eval', '=> 4' }), out.text())
    end)

    it(':Storm eval resolves names in the package of the file', function()
        vim.cmd.Storm({ 'eval', 'answer()' })
        assert.is_true(out.wait_for('=> 42'))
    end)

    it(':Storm eval reports errors', function()
        vim.cmd.Storm({ 'eval', 'nope(' })
        local function errors()
            return vim.tbl_filter(function(n) return n.msg:find('syntax error') end, out.notifications)
        end
        assert.is_true(wait(function() return #errors() > 0 end))
        local errors = errors()
        assert.are.equal(1, #errors)
        assert.are.equal(vim.log.levels.ERROR, errors[1].level)
    end)

    it('<Plug>(storm-eval) in visual mode evaluates the selection', function()
        vim.keymap.set('x', '<F5>', '<Plug>(storm-eval)', { buffer = bufnr })
        vim.api.nvim_win_set_cursor(0, { ANSWER_LINE, 4 }) -- "40 + 2;"
        vim.api.nvim_feedkeys(vim.keycode('v5l<F5>'), 'x', false)
        assert.is_true(out.wait_for('=> 42'))
        vim.keymap.del('x', '<F5>', { buffer = bufnr })
    end)

    it(':Storm run shows the results and output of all functions as they arrive', function()
        vim.cmd.Storm({ 'run' })
        assert.is_true(out.wait_for('demo%.greet: <void>'))
        local lines = echoed_lines(out)
        assert.is_true(vim.tbl_contains(lines, 'demo.answer: 42'))
        assert.is_true(vim.tbl_contains(lines, 'Hello from Storm'))
        assert.is_true(#out.echoes < #lines, 'lines arriving together are echoed together')
    end)

    it(':Storm run cursor runs the function at the cursor and shows its result', function()
        vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- in greet()
        vim.cmd.Storm({ 'run', 'cursor' })
        assert.is_true(out.wait_for('=> <void>'))
        assert.is_true(echoed_in_order(out, { 'Hello from Storm', '=> <void>' }), out.text())
    end)

    it('type errors found by :Storm run become diagnostics, cleared after fixing', function()
        set_answer('    "not an int";')
        vim.cmd.Storm({ 'reload' })
        assert.is_true(out.wait_for('Reloaded 1 files'))
        vim.cmd.Storm({ 'run' })
        assert.is_true(wait(function() return #compile_diagnostics() > 0 end))
        local diagnostic = compile_diagnostics()[1]
        assert.are.equal(ANSWER_LINE - 1, diagnostic.lnum)
        assert.matches('Type error: Expected core%.Int but got core%.Str', diagnostic.message)
        assert.is_true(out.wait_for('1 error, see :Storm errors'))
        assert.are.same({}, vim.fn.getqflist(), 'the quickfix list is only filled by :Storm errors')

        -- :Storm errors shows them too
        vim.cmd.Storm({ 'errors' })
        assert.is_true(wait(function() return #vim.fn.getqflist() > 0 end))
        assert.matches('Type error', vim.fn.getqflist()[1].text)
        vim.cmd('cclose')

        set_answer('    40 + 2;')
        vim.cmd.Storm({ 'reload' })
        assert.is_true(wait(function() return #compile_diagnostics() == 0 end))
    end)

    it(':Storm reload and :Storm reload package report what was reloaded', function()
        vim.cmd.Storm({ 'reload' })
        assert.is_true(out.wait_for('Storm: Reloaded 1 files'))
        vim.cmd.Storm({ 'reload', 'package' })
        assert.is_true(out.wait_for('Storm: Reloaded 0 files and 1 packages'))
        for _, n in ipairs(out.notifications) do
            if n.msg:find('Reloaded') then assert.are.equal(vim.log.levels.INFO, n.level) end
        end
    end)

    it(':Storm reload {file} reloads the given files', function()
        vim.cmd.Storm({ 'reload', '%' })
        assert.is_true(out.wait_for('Storm: Reloaded 1 files'))
        local completions = require('storm-mode.commands')._complete_command('', 'Storm reload ', 0)
        assert.are.equal('package', completions[1])
        assert.is_true(#completions > 1, 'file names are completed too')
    end)

    it('reloaded buffer content is used by run', function()
        set_answer('    40 + 3;')
        vim.cmd.Storm({ 'reload' })
        assert.is_true(out.wait_for('Reloaded'))
        vim.cmd.Storm({ 'run' })
        assert.is_true(out.wait_for('demo%.answer: 43'))
    end)
end)
