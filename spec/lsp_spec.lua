local spy = require('busted').spy

describe('lsp', function()
    local Enc = require('storm-mode.encoder')
    local Handlers = require('storm-mode.handlers')
    local Lsp = require('storm-mode.lsp')

    local match = require('luassert.match')
    local sym = require('storm-mode.sym').literal

    ---Wait for spy to be called once, timing out after 500ms
    ---@param modspy table
    ---@return boolean
    local function wait_called(modspy)
        return vim.wait(500, function() return #modspy.calls > 0 end, 20)
    end

    before_each(function()
        Enc._next_symid = 1
    end)

    local function is_msgtype(_, arguments)
        return function(value)
            return arguments[1] == value[1]
        end
    end

    it('starts storm, gets color data, and exits', function()
        assert:register("matcher", "msgtype", is_msgtype)
        local handlers_resolve = spy.on(Handlers, 'resolve')
        local lsp_on_stdout = spy.on(Lsp, '_on_stdout')
        local lsp_on_exit = spy.on(Lsp, '_on_exit')

        -- Check Storm starts, Storm will output to its stdout on startup finish
        vim.cmd.edit('spec/test_data/small_source.bs')
        vim.cmd.Storm('start')
        assert.True(wait_called(lsp_on_stdout))
        assert.spy(lsp_on_stdout).was_called_with(nil, 'Language server started.\n')

        -- Check color data is sent
        assert.True(wait_called(handlers_resolve))
        assert.spy(handlers_resolve).was.called_with(match.is_msgtype(sym 'color'))

        -- Check Storm exits cleanly
        vim.cmd.Storm('quit')
        assert.True(wait_called(lsp_on_exit))
        assert.spy(lsp_on_exit).was_called_with(match._, 0)

        handlers_resolve:revert()
        lsp_on_stdout:revert()
        lsp_on_exit:revert()
    end)
end)
