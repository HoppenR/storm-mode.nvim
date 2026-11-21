---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- The cached buffer content must track the real buffer through every kind of
-- edit, and every edit sent to Storm must have a unique, increasing id.
-- Storm is not started: Lsp.send is stubbed.
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

local function read_buffer(bufnr) return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n' end

describe('buffer sync', function()
    local lsp_send_stub, lsp_start_stub
    local bufnr
    local errors
    local orig_on_bytes
    local orig_notify

    setup(function()
        lsp_send_stub = stub.new(Lsp, 'send')
        -- set_mode and flush start Storm; these tests don't use a real one
        lsp_start_stub = stub.new(Lsp, 'start')
        -- The out-of-sync fallback resends the whole buffer, which would hide
        -- bugs in change tracking: treat its warning as an error.
        orig_notify = vim.notify
        vim.notify = function(msg, ...)
            if tostring(msg):find('out of sync') then table.insert(errors, msg) end
            return orig_notify(msg, ...)
        end
        -- Errors inside on_bytes are caught by Neovim and only printed;
        -- record them so they fail the test.
        orig_on_bytes = Buffer.on_bytes
        Buffer.on_bytes = function(...)
            local ok, res = pcall(orig_on_bytes, ...)
            if not ok then
                table.insert(errors, tostring(res))
                return
            end
            return res
        end
    end)

    teardown(function()
        vim.notify = orig_notify
        Buffer.on_bytes = orig_on_bytes
        lsp_send_stub:revert()
        lsp_start_stub:revert()
    end)

    before_each(function()
        errors = {}
        lsp_send_stub:clear()
        bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn.readfile('spec/test_data/small_source.bs'))
        vim.cmd('let &undolevels = &undolevels') -- don't undo the initial content
        Buffer.set_mode(bufnr)
        vim.bo[bufnr].indentexpr = '' -- Storm is stubbed: indent requests would time out
    end)

    after_each(function() vim.api.nvim_buf_delete(bufnr, { force = true }) end)

    ---Run normal-mode keys as one step and check the invariants
    ---@param quiet boolean? ignore editor errors (e.g. a motion past the buffer end)
    local function step(keys, quiet)
        vim.cmd((quiet and 'silent! ' or '') .. 'execute "normal! ' .. keys .. '"')
        vim.cmd('let &undolevels = &undolevels')
        assert.are.same({}, errors, keys .. ': errors in on_bytes or flush')
        assert.are.equal(read_buffer(bufnr), Buffer._debug_state(bufnr).content, keys .. ': cached content out of sync')
    end

    ---Edit ids sent to Storm must be 1, 2, 3, ... with no repeats
    local function assert_edit_ids_increasing()
        local expected = 1
        for _, call in ipairs(lsp_send_stub.calls) do
            local msg = call.vals[1]
            if msg[1] == sym 'edit' then
                assert.are.equal(expected, msg[3], 'edit ids must be unique and increasing')
                expected = expected + 1
            end
        end
        assert.are.equal(expected - 1, Buffer._debug_state(bufnr).last_edit_id)
    end

    it('starts with the trailing newline and edit id 0', function()
        assert.are.equal(read_buffer(bufnr), Buffer._debug_state(bufnr).content)
        assert.are.equal(0, Buffer._debug_state(bufnr).last_edit_id)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'open'))
    end)

    it('o on the last line and undo', function()
        step('Goabc def ghi\\<Esc>')
        step('u')
        assert_edit_ids_increasing()
    end)

    -- Undo/redo that replays several changes at once fires on_bytes after the
    -- buffer is already in its final state, so the text must be read on flush.
    it('o on the last line, undo and redo', function()
        step('Goabc def ghi\\<Esc>')
        step('u')
        step('\\<C-r>')
        assert_edit_ids_increasing()
    end)

    it('dd on the last line and undo', function()
        step('Gdd')
        step('u')
        assert_edit_ids_increasing()
    end)

    it('delete the whole buffer and undo', function()
        step('ggdG')
        step('u')
        assert_edit_ids_increasing()
    end)

    it('delete almost everything one character at a time', function()
        step('gg' .. string.rep('x', 200))
        step('Gdd')
        step('ggdG')
        assert_edit_ids_increasing()
    end)

    it('fast typing in one insert, then undo', function()
        step('ggA' .. string.rep('ab ', 30) .. '\\<CR>' .. string.rep('cd ', 30) .. '\\<Esc>')
        step('u')
        assert_edit_ids_increasing()
    end)

    it('multi-line visual change and undo', function()
        step('ggVjcnew text\\<Esc>')
        step('u')
        assert_edit_ids_increasing()
    end)

    it('substitute across lines and undo', function()
        vim.cmd('%s/Int/Integer/g')
        assert.are.same({}, errors)
        assert.are.equal(read_buffer(bufnr), Buffer._debug_state(bufnr).content)
        vim.cmd('let &undolevels = &undolevels')
        step('u')
        assert_edit_ids_increasing()
    end)

    it('random edits, undos and redos stay in sync', function()
        math.randomseed(12345)
        local actions = {
            function() return 'i' .. ('xyz'):rep(math.random(1, 3)) .. '\\<Esc>' end,
            function() return 'o' .. 'new line' .. '\\<Esc>' end,
            function() return 'x' end,
            function() return 'dd' end,
            function() return 'J' end,
            function() return 'yyp' end,
            function() return 'u' end,
            function() return 'uu' end,
            function() return '\\<C-r>' end,
            function() return 'Vjd' end,
            function() return 'cwreplaced\\<Esc>' end,
        }
        for _ = 1, 300 do
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            local row = math.random(1, line_count)
            local motion = row .. 'G' .. math.random(0, 20) .. '|'
            step(motion .. actions[math.random(#actions)]() .. '\\<Esc>', true)
        end
        -- several commands before a single flush
        vim.cmd('normal! ggdd')
        vim.cmd('normal! Gyyp')
        vim.cmd('normal! u')
        vim.cmd('silent! %s/e/EE/g')
        assert.are.equal(read_buffer(bufnr), Buffer._debug_state(bufnr).content)
        assert_edit_ids_increasing()
    end)

    it('one undo with several changes gets several distinct edit ids', function()
        step('ggx')
        step('jx')
        vim.cmd('normal! ggxjx') -- two changes in one undo block
        vim.cmd('let &undolevels = &undolevels')
        local before = Buffer._debug_state(bufnr).last_edit_id
        step('u')
        assert.True(
            Buffer._debug_state(bufnr).last_edit_id >= before + 2,
            'each change of the undo must get its own edit id'
        )
        assert_edit_ids_increasing()
    end)

    it('turning storm-mode off and on does not record changes twice', function()
        Buffer.set_mode(bufnr)
        Buffer.unset_mode(bufnr)
        Buffer.set_mode(bufnr)
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { 'X' })
        local state = Buffer._debug_state(bufnr)
        assert.are.equal(1, state.last_edit_id)
        assert.are.equal(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n', state.content)
    end)
end)
