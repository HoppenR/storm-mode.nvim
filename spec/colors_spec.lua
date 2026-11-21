---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Coloring buffers from Storm's color messages: first with Storm stubbed out,
-- then against a real Storm.
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal
local small_extmarks = {
    { 1, 0, 0 },
    { 2, 0, 4 },
    { 3, 0, 18 },
    { 4, 0, 22 },
    { 5, 0, 27 },
    { 6, 0, 31 },
    { 7, 1, 4 },
    { 8, 1, 11 },
    { 9, 1, 17 },
}
local small_bufcolors = {
    { 3, sym 'type-name' },
    { 1, vim.NIL },
    { 13, sym 'fn-name' },
    { 1, vim.NIL },
    { 3, sym 'type-name' },
    { 1, vim.NIL },
    { 3, sym 'var-name' },
    { 2, vim.NIL },
    { 3, sym 'type-name' },
    { 1, vim.NIL },
    { 3, sym 'var-name' },
    { 8, vim.NIL },
    { 6, sym 'keyword' },
    { 1, vim.NIL },
    { 3, sym 'var-name' },
    { 3, vim.NIL },
    { 3, sym 'var-name' },
    { 3, vim.NIL },
}

---Extmarks as {start_row, start_col, end_row, end_col, hl_group}
local function marks(bufnr)
    local result = {}
    for _, m in
        ipairs(
            vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_get_namespaces()['storm-mode'], 0, -1, { details = true })
        )
    do
        table.insert(result, { m[2], m[3], m[4].end_row, m[4].end_col, m[4].hl_group })
    end
    return result
end

describe('colors', function()
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

    it('applies colors', function()
        Buffer.set_mode(bufnr)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'open'))
        assert.False(Lsp.is_running())
        Buffer.apply_colors(Buffer.storm_id(bufnr), small_bufcolors, 0, 0)
        assert.are_same(
            small_extmarks,
            vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_get_namespaces()['storm-mode'], 0, -1, {})
        )
    end)

    it('uncolored spans remove old colors, but not touching neighbours', function()
        Buffer.set_mode(bufnr)
        local id = Buffer.storm_id(bufnr)
        Buffer.apply_colors(id, small_bufcolors, 0, 0)
        -- Recolor from character 4: "addTwoNumbers" is no longer a function name
        Buffer.apply_colors(id, { { 13, vim.NIL } }, 0, 4)
        local m = marks(bufnr)
        assert.are.same({ 0, 0, 0, 3, 'Type' }, m[1], '"Int" before the span is kept')
        assert.are.same({ 0, 18, 0, 21, 'Type' }, m[2], '"Int" after the span is kept')
        assert.are.equal(#small_extmarks - 1, #m)
    end)

    it('text typed next to a token is not colored like it', function()
        Buffer.set_mode(bufnr)
        Buffer.apply_colors(Buffer.storm_id(bufnr), small_bufcolors, 0, 0)
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { 'X' }) -- before "Int"
        vim.api.nvim_buf_set_text(bufnr, 0, 4, 0, 4, { 'Y' }) -- after "Int"
        assert.are.same({ 0, 1, 0, 4, 'Type' }, marks(bufnr)[1])
    end)

    it('keeps the snapshot for later color messages of the same edit', function()
        Buffer.set_mode(bufnr)
        local id = Buffer.storm_id(bufnr)
        -- Storm first sends an uncolored update, then the real colors
        Buffer.apply_colors(id, { { 62, vim.NIL } }, 0, 0)
        assert.are.same({}, marks(bufnr))
        Buffer.apply_colors(id, small_bufcolors, 0, 0)
        assert.are.equal(#small_extmarks, #marks(bufnr))
    end)
end)

local function wait_condition(cond, timeout_ms)
    local ok, _ = vim.wait(timeout_ms or 1000, cond, 20)
    return ok
end

local function read_buffer(bufnr) return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n' end

describe('colors from Storm', function()
    local bufnr
    local lsp_stdout_spy
    local lsp_exit_spy
    local orig_apply_colors
    ---@type {sbufnr: integer, colors: table, edit_id: integer, start_ch: integer}[]
    local color_calls
    ---@type string[]
    local color_errors

    ---apply_colors runs inside a vim.schedule callback, so its errors would only
    ---be printed. Record them so tests can assert on them.
    local function find_color_call(edit_id)
        for _, call in ipairs(color_calls) do
            if call.edit_id == edit_id then return call end
        end
    end

    local function last_edit_id() return Buffer._debug_state(bufnr).last_edit_id end

    ---Wait for Storm to answer the most recent edit, then check the invariants
    local function wait_and_check(what)
        local id = last_edit_id()
        assert.True(
            wait_condition(function() return find_color_call(id) ~= nil end, 3000),
            string.format('%s: no color response for edit_id=%d', what, id)
        )
        assert.are.same({}, color_errors, what .. ': apply_colors raised errors')
        assert.are.equal(
            read_buffer(bufnr),
            Buffer._debug_state(bufnr).content,
            what .. ': cached content out of sync with buffer'
        )

        -- Neovim moves marks to (line_count, 0) when everything after them is
        -- deleted, so that position is valid; anything beyond it is not.
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        for _, em in
            ipairs(
                vim.api.nvim_buf_get_extmarks(
                    bufnr,
                    vim.api.nvim_get_namespaces()['storm-mode'],
                    0,
                    -1,
                    { details = true }
                )
            )
        do
            local d = em[4]
            local function valid(row, col) return row < line_count or (row == line_count and col == 0) end
            local in_bounds = valid(em[2], em[3]) and valid(d.end_row, d.end_col)
            assert.True(
                in_bounds,
                string.format(
                    '%s: extmark (%d,%d)-(%d,%d) out of bounds (%d lines)',
                    what,
                    em[2],
                    em[3],
                    d.end_row,
                    d.end_col,
                    line_count
                )
            )
        end
    end

    setup(function()
        color_calls, color_errors = {}, {}
        orig_apply_colors = Buffer.apply_colors
        Buffer.apply_colors = function(sbufnr, colors, edit_id, start_ch)
            table.insert(
                color_calls,
                { sbufnr = sbufnr, colors = vim.deepcopy(colors), edit_id = edit_id, start_ch = start_ch }
            )
            local ok, err = pcall(orig_apply_colors, sbufnr, colors, edit_id, start_ch)
            if not ok then table.insert(color_errors, tostring(err)) end
        end
        lsp_stdout_spy = spy.on(Lsp, '_on_stdout')
        lsp_exit_spy = spy.on(Lsp, '_on_exit')

        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()

        vim.cmd.Storm('start')
        assert.True(
            wait_condition(function() return #lsp_stdout_spy.calls > 0 end, 2000),
            'Storm did not start (no stdout within 2s)'
        )
        assert.True(
            wait_condition(function() return #color_calls > 0 end, 2000),
            'Storm did not send initial colors within 2s'
        )
    end)

    teardown(function()
        if Lsp.is_running() then
            vim.cmd.Storm('quit')
            assert.True(wait_condition(function() return #lsp_exit_spy.calls > 0 end, 2000))
        end
        vim.api.nvim_buf_delete(bufnr, { force = true })
        Buffer.apply_colors = orig_apply_colors
        lsp_stdout_spy:revert()
        lsp_exit_spy:revert()
    end)

    before_each(function()
        vim.api.nvim_set_current_buf(bufnr)
        -- Tests run in random order and share the buffer: restore the file content
        local original = vim.fn.readfile('spec/test_data/small_source.bs')
        if not vim.deep_equal(original, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) then
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original)
            wait_and_check('restore content')
        end
        vim.cmd('let &undolevels = &undolevels') -- undo break between tests
    end)

    it('Storm start sets extmarks for edit_id=0', function()
        local initial_call = find_color_call(0)
        assert.is_not_nil(initial_call, 'Storm must answer the open message with edit_id=0')
        assert.are_equal(0, initial_call.start_ch, 'start_ch should be 0 for full-buffer coloring')
        assert.True(#initial_call.colors > 0, 'Storm should send at least one color span')

        -- If before_each restored the content, Storm first answers with an
        -- uncolored span and sends the colors for the same edit ~0.7s later
        wait_condition(
            function()
                return #vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_get_namespaces()['storm-mode'], 0, -1, {}) > 0
            end,
            3000
        )
        assert.True(
            #vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_get_namespaces()['storm-mode'], 0, -1, {}) > 0,
            'no extmarks set after initial apply_colors'
        )
        assert.are.same({}, color_errors)
    end)

    it('single edit gets a color response with the next edit id', function()
        local before = last_edit_id()
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { ' ' })
        assert.are.equal(before + 1, last_edit_id())
        wait_and_check('single edit')
        assert.True(#vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_get_namespaces()['storm-mode'], 0, -1, {}) > 0)
    end)

    it('rapid successive edits are all answered and placed correctly', function()
        local before = last_edit_id()
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 1, { 'Z' })
        vim.api.nvim_buf_set_text(bufnr, 1, 0, 1, 1, { 'Z' })
        assert.are.equal(before + 2, last_edit_id())
        assert.True(
            wait_condition(
                function() return find_color_call(before + 1) ~= nil and find_color_call(before + 2) ~= nil end,
                3000
            ),
            'Storm did not respond to both edits within 3s'
        )
        wait_and_check('rapid edits')
    end)

    it('typing at the end of the buffer and undoing', function()
        vim.cmd('normal! Goint x = 1;\027')
        vim.cmd('let &undolevels = &undolevels')
        vim.cmd('normal! ofoo bar baz\027')
        vim.cmd('let &undolevels = &undolevels')
        wait_and_check('type at end')
        vim.cmd('normal! u')
        wait_and_check('undo')
        vim.cmd('normal! u')
        wait_and_check('second undo')
    end)

    it('redo after undo at the end of the buffer', function()
        vim.cmd('normal! Goint x = 1;\027')
        vim.cmd('let &undolevels = &undolevels')
        wait_and_check('type at end')
        vim.cmd('normal! u')
        wait_and_check('undo')
        vim.cmd('execute "normal! \\<C-r>"')
        wait_and_check('redo')
    end)

    it('substitute across the buffer and undo', function()
        vim.cmd('%s/lhs/left/g')
        vim.cmd('let &undolevels = &undolevels')
        wait_and_check('substitute')
        vim.cmd('normal! u')
        wait_and_check('undo substitute')
    end)

    it('deleting the whole buffer and undoing', function()
        vim.cmd('normal! ggdG')
        wait_and_check('ggdG')
        vim.cmd('normal! u')
        wait_and_check('undo ggdG')
    end)

    it('deleting the last line and undoing', function()
        vim.cmd('normal! Gdd')
        wait_and_check('dd last line')
        vim.cmd('normal! u')
        wait_and_check('undo dd')
    end)
end)
