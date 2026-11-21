---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Storm's output can arrive while Neovim runs an 'omnifunc' or 'indentexpr'
-- (which wait for Storm's replies). Text is locked then (E565): windows can't
-- be opened, but messages and notifications can be shown.
local Output = require('storm-mode.output')

---Run `fn` inside an omnifunc, where text is locked
local function in_textlock(fn)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    local ok, err = true, nil
    package.loaded['storm-test-omnifunc'] = {
        omnifunc = function(findstart)
            if findstart == 1 then return 0 end
            ok, err = pcall(fn)
            return {}
        end,
    }
    vim.bo[bufnr].omnifunc = "v:lua.require'storm-test-omnifunc'.omnifunc"
    vim.api.nvim_feedkeys(vim.keycode('i<C-x><C-o><Esc>'), 'tx', false)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    package.loaded['storm-test-omnifunc'] = nil
    return ok, err
end

describe('output', function()
    local out

    before_each(function()
        vim.cmd('silent! only')
        out = StormTest.record()
    end)

    after_each(function() out.restore() end)

    it('when_unlocked opens a window after the textlock instead of failing', function()
        local scratch = vim.api.nvim_create_buf(false, true)
        local ok, err = in_textlock(function()
            Output.when_unlocked(function() vim.api.nvim_open_win(scratch, false, { split = 'right' }) end)
        end)
        assert.is_true(ok, tostring(err))
        assert.is_true(vim.wait(1000, function() return #vim.fn.win_findbuf(scratch) == 1 end, 10))
        vim.api.nvim_buf_delete(scratch, { force = true })
    end)

    it('when_unlocked passes on other errors', function()
        assert.has_error(function()
            Output.when_unlocked(function() error('boom') end)
        end, 'boom')
    end)

    it('echo and notify work while text is locked', function()
        local ok, err = in_textlock(function()
            Output.echo('echoed\n')
            Output.notify('notified')
        end)
        assert.is_true(ok, tostring(err))
        assert.are.same({ { text = 'echoed' } }, out.echoes)
        assert.are.same({ { msg = 'Storm: notified', level = vim.log.levels.INFO } }, out.notifications)
    end)

    it('echo uses the message kind on Neovim 0.12', function()
        Output.echo('a long dump', { kind = 'list_cmd' })
        local expected = vim.fn.has('nvim-0.12') == 1 and 'list_cmd' or nil
        assert.are.same({ { text = 'a long dump', kind = expected } }, out.echoes)
    end)

    it('does not show empty or whitespace-only output', function()
        Output.echo('\n\n')
        -- A piece of Storm's output can be just the indentation of a line
        Output.echo('                        \n')
        Output.notify('')
        Output.notify('   \n')
        assert.are.same({}, out.echoes)
        assert.are.same({}, out.notifications)
    end)

    it('hands on streamed output in blocks of whole lines', function()
        local blocks = {}
        local stream = Output.stream(function(block) table.insert(blocks, block) end)
        -- Pieces as Storm sends them: a line split anywhere, indentation alone
        stream:push('Hello ')
        stream:push('from\r\n                        ')
        stream:push('\nStorm\nlast')
        assert.are.same({}, blocks, 'nothing before the batch delay')
        assert.is_true(vim.wait(500, function() return #blocks > 0 end, 10))
        assert.are.same(
            { 'Hello from\n                        \nStorm' },
            blocks,
            'one block, not one message per piece'
        )
        stream:flush()
        assert.are.same({ 'Hello from\n                        \nStorm', 'last' }, blocks)
    end)

    it('hands on output that arrives later as a new block', function()
        local blocks = {}
        local stream = Output.stream(function(block) table.insert(blocks, block) end)
        stream:push('first\n')
        assert.is_true(vim.wait(500, function() return #blocks == 1 end, 10))
        stream:push('second\n')
        stream:flush()
        assert.are.same({ 'first', 'second' }, blocks)
    end)

    it('picks notification levels for Storm output', function()
        assert.are.equal(vim.log.levels.INFO, Output.level_of('Reloaded 1 files'))
        assert.are.equal(vim.log.levels.WARN, Output.level_of('Warning: No package found'))
        assert.are.equal(vim.log.levels.WARN, Output.level_of('WARNING storm::File: not in a package'))
        assert.are.equal(vim.log.levels.ERROR, Output.level_of('While processing (debug):\nboom'))
        assert.are.equal(vim.log.levels.ERROR, Output.level_of('@a.bs(1-2): Type error: x'))
    end)
end)
