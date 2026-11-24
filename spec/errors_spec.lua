---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
local Errors = require('storm-mode.errors')
local Lsp = require('storm-mode.lsp')

local function wait(cond, ms) return vim.wait(ms or StormTest.TIMEOUT_MS, cond, 20) end

describe('error parsing', function()
    local path = vim.fn.fnamemodify('spec/test_data/small_source.bs', ':p')

    it('finds error locations', function()
        -- small_source.bs: line 2 starts at character 38, `lhs` at 49-52
        local items = Errors.parse(table.concat({
            'Some output',
            '@' .. path .. '(49-52): Type error: No such thing',
            '  p1> @' .. path .. '(0): Syntax error: Unexpected thing',
            '@' .. path .. '(38-39): here',
            '@/does/not/exist.bs(1-2): Syntax error: Missing',
            '@' .. path .. '(3-4): not an error',
        }, '\n'))
        assert.are.same({
            {
                filename = path,
                lnum = 2,
                col = 12,
                end_lnum = 2,
                end_col = 15,
                text = 'Type error: No such thing',
                type = 'E',
            },
            { filename = path, lnum = 1, col = 1, text = 'Syntax error: Unexpected thing', type = 'E' },
            { filename = path, lnum = 2, col = 1, end_lnum = 2, end_col = 2, text = 'here', type = 'I' },
        }, items)
    end)

    it('condenses the list of expected tokens', function()
        local lines = { '@' .. path .. "(37-38): Syntax error: Unexpected '}'. Expected:" }
        for i = 1, 8 do
            table.insert(lines, '  "t' .. i .. '"')
        end
        table.insert(lines, 'after the list')
        local items = Errors.parse(table.concat(lines, '\n'))
        assert.are.equal(1, #items)
        assert.are.equal(
            [[Syntax error: Unexpected '}'. Expected: "t1", "t2", "t3", "t4", "t5" (+3 more)]],
            items[1].text
        )
    end)

    it('turns errors into diagnostics, also for files that are not open', function()
        local file = vim.fn.tempname() .. '.bs'
        vim.fn.writefile({ 'Int f() {', '    1;', '}' }, file)
        local out = StormTest.record()
        Errors.from_compile_output('lib.f: Error:\n@' .. file .. '(14-15): Type error: X\n', {})
        out.restore()
        local bufnr = vim.fn.bufnr(file)
        assert.is_false(vim.api.nvim_buf_is_loaded(bufnr), 'the file is not opened')
        local diagnostics = vim.diagnostic.get(bufnr, { namespace = Errors.compile_ns })
        assert.are.equal(1, #diagnostics)
        assert.are.equal(1, diagnostics[1].lnum)
        assert.matches('1 error, see :Storm errors', out.text())

        -- They show up when the file is opened
        vim.cmd.edit(file)
        assert.are.equal(1, #vim.diagnostic.get(0, { namespace = Errors.compile_ns }))
        -- Not left for later tests: Neovim can some times keep the diagnostics
        -- of a deleted buffer
        vim.diagnostic.reset(Errors.compile_ns, bufnr)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('leaves diagnostics of buffers that no longer exist out of the quickfix list', function()
        -- A Storm diagnostic that outlives its buffer: Neovim removes them when a
        -- buffer is wiped, unless that's some times skipped or delayed
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.diagnostic.set(Errors.compile_ns, bufnr, { { lnum = 0, col = 0, message = 'stale' } })
        vim.cmd('noautocmd bwipeout! ' .. bufnr)
        assert.are.equal(1, #vim.diagnostic.get(nil, { namespace = Errors.compile_ns }), 'stale diagnostic')

        local out = StormTest.record()
        local ok, err = pcall(Errors.to_quickfix)
        out.restore()
        vim.diagnostic.reset(Errors.compile_ns)
        assert.is_true(ok, err)
        assert.matches('Storm: no errors', out.text())
    end)

    it(
        'skips locations in evaluated expressions',
        function() assert.are.same({}, Errors.parse('@./(2-3): Syntax error: Can not find an implementation')) end
    )
end)

describe('errors from Storm', function()
    local bufnr, out

    before_each(function()
        vim.cmd('silent! only')
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()
        vim.cmd.Storm('start')
        vim.fn.setqflist({}, 'f')
        out = StormTest.record()
    end)

    after_each(function()
        out.restore()
        vim.cmd('silent! cclose')
        vim.cmd.Storm('quit')
        wait(function() return not Lsp.is_running() end)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    local function syntax_diagnostics() return vim.diagnostic.get(bufnr, { namespace = Errors.syntax_ns }) end
    local function break_buffer() vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { '    return lhs + ;' }) end
    local function fix_buffer() vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { '    return lhs + rhs;' }) end

    it(':Storm errors checks the buffer and fills the quickfix list', function()
        break_buffer()
        vim.cmd.Storm({ 'errors' })
        assert.is_true(wait(function() return #vim.fn.getqflist() > 0 end))
        local qf = vim.fn.getqflist({ title = 0, items = 0 })
        assert.are.equal('Storm errors', qf.title)
        assert.are.equal(2, qf.items[1].lnum)
        assert.matches('Syntax error', qf.items[1].text)
        assert.are.equal(1, #syntax_diagnostics())
        assert.are.equal('quickfix', vim.bo[vim.api.nvim_get_current_buf()].buftype, 'the quickfix window is open')
    end)

    it(':Storm errors after fixing the error shows no stale errors', function()
        break_buffer()
        vim.cmd.Storm({ 'errors' })
        assert.is_true(wait(function() return #vim.fn.getqflist() > 0 end))
        vim.cmd('wincmd p')

        fix_buffer()
        vim.cmd.Storm({ 'errors' })
        assert.is_true(out.wait_for('Storm: no errors'))
        local qf = vim.fn.getqflist({ title = 0, items = 0 })
        assert.are.equal('Storm errors', qf.title)
        assert.are.same({}, qf.items)
        assert.are.same({}, syntax_diagnostics())
        assert.are.equal(1, vim.fn.getqflist({ nr = '$' }).nr, 'the list was replaced, not added to')
        assert.are.equal(0, vim.fn.getqflist({ winid = 0 }).winid, 'the quickfix window is closed')
    end)

    it('checks the buffer for syntax errors in the background, without the quickfix list', function()
        break_buffer()
        vim.api.nvim_exec_autocmds('InsertLeave', { buffer = bufnr })
        assert.is_true(wait(function() return #syntax_diagnostics() == 1 end))
        local diagnostic = syntax_diagnostics()[1]
        assert.are.equal(1, diagnostic.lnum)
        assert.are.equal(vim.diagnostic.severity.ERROR, diagnostic.severity)
        assert.are.same({}, vim.fn.getqflist(), 'the quickfix list is left alone')

        fix_buffer()
        vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
        assert.is_true(wait(function() return #syntax_diagnostics() == 0 end))
        assert.are.same({}, out.echoes, 'background checks print nothing')
    end)

    it('does not check in the background when diagnostics are off', function()
        local Config = require('storm-mode.config')
        rawset(Config, 'diagnostics', false) -- shadows the configured value
        break_buffer()
        vim.api.nvim_exec_autocmds('InsertLeave', { buffer = bufnr })
        vim.wait(1000)
        rawset(Config, 'diagnostics', nil)
        assert.are.same({}, syntax_diagnostics())
    end)

    it('removes the diagnostics when storm-mode is turned off', function()
        break_buffer()
        vim.cmd.Storm({ 'errors' })
        assert.is_true(wait(function() return #syntax_diagnostics() == 1 end))
        vim.api.nvim_set_current_buf(bufnr)
        vim.cmd.Storm('close')
        assert.are.same({}, syntax_diagnostics())
    end)

    it(':Storm debug error prints what Storm says', function()
        break_buffer()
        vim.cmd.Storm({ 'debug', 'error' })
        assert.is_true(out.wait_for('Syntax error'))
        assert.matches('Expected:', out.echoes[1].text, 'the raw output')
        if vim.fn.has('nvim-0.12') == 1 then assert.are.equal('list_cmd', out.echoes[1].kind) end
    end)
end)
