---@diagnostic disable: undefined-global
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

-- TODO: rewrite vim.cmd('norm ...') with vim.api.nvim_feedkeys

---Collect multiple calls to Buffer.on_bytes containing simple contiguous
---edits into a single string, and compare to an expected string and length
---@alias storm-mode.lsp.message.edit [storm-mode.sym, integer, integer, integer, integer, string]
---@param lsp_send_stub busted.stub
---@param expected string[]
---@param ndeleted integer
---@return boolean correct
---@return string? errmsg
local function match_accumulated_changes(lsp_send_stub, expected, ndeleted)
    -- TODO: rewrite this such that the ranges in the array representing
    -- the edits, are from OLD_pos and OLD_chars. Then merge based on that
    -- Can also use the difference in changedticks to distinguish things...
    ---@type {pos: integer, chars: integer, text: string}[]
    local insertions = {}
    local deletedchars = 0
    local postdeletions = 0
    for i = 1, #lsp_send_stub.calls do
        local args = lsp_send_stub.calls[i].vals[1]
        local type = args[1]
        if type ~= sym 'edit' then
            goto continue
        end
        ---@cast args storm-mode.lsp.message.edit
        local start_pos  = args[4]
        local end_pos    = args[5]
        local text_chunk = args[6]
        local chars      = vim.fn.strchars(text_chunk)
        deletedchars     = deletedchars + end_pos - start_pos
        local inserted   = false
        for ix, entry in ipairs(insertions) do
            if start_pos == entry.pos then
                insertions[ix] = { pos = entry.pos, chars = chars + entry.chars, text = text_chunk .. entry.text }
                inserted = true
                break
            elseif start_pos == entry.pos + entry.chars then
                insertions[ix] = { pos = entry.pos, chars = entry.chars + chars, text = entry.text .. text_chunk }
                inserted = true
                break
            elseif start_pos > entry.pos and start_pos < entry.pos + entry.chars then
                local precharix = start_pos - entry.pos
                local pre = vim.fn.strcharpart(entry.text, 0, precharix)
                local post = vim.fn.strcharpart(entry.text, precharix + end_pos - start_pos)
                local text = pre .. text_chunk .. post
                postdeletions = postdeletions + end_pos - start_pos
                insertions[ix] = { pos = entry.pos, chars = entry.chars + chars, text = text }
                inserted = true
                break
            end
        end
        if not inserted then
            table.insert(insertions, { pos = start_pos, chars = chars, text = text_chunk })
        end
        ::continue::
    end
    if #insertions ~= #expected then
        return false, ('Expected range count mismatch:%d\ndoes not match expected:%d')
            :format(#insertions, #expected)
    end
    table.sort(insertions, function(a, b) return a.pos < b.pos end)
    local expectedinsertions = 0
    local actualinsertions = 0
    for i = 1, #insertions do
        expectedinsertions = expectedinsertions + vim.fn.strchars(insertions[i].text)
        actualinsertions = actualinsertions + insertions[i].chars
        if insertions[i].text ~= expected[i] then
            return false, ('Accumulated text:%q\ndoes not match expected:%q')
                :format(insertions[i].text, expected[i])
        end
    end
    if expectedinsertions ~= actualinsertions - postdeletions then
        return false, ('Expected char length mismatch: got %d, expected %d')
            :format(expectedinsertions, actualinsertions)
    end
    if deletedchars ~= ndeleted then
        return false, ('Expected char deletion mismatch: got %d, expected %d')
            :format(deletedchars, ndeleted)
    end

    return true
end

local small_extmarks = {
    { 1, 0, 0 }, { 2, 0, 4 }, { 3, 0, 18 }, { 4, 0, 22 }, { 5, 0, 27 }, { 6, 0, 31 },
    { 7, 1, 4 }, { 8, 1, 11 }, { 9, 1, 17 },
}
local small_bufcolors = {
    { 3,  sym 'type-name' }, { 1, vim.NIL },
    { 13, sym 'fn-name' }, { 1, vim.NIL },
    { 3, sym 'type-name' }, { 1, vim.NIL },
    { 3, sym 'var-name' }, { 2, vim.NIL },
    { 3, sym 'type-name' }, { 1, vim.NIL },
    { 3, sym 'var-name' }, { 8, vim.NIL },
    { 6, sym 'keyword' }, { 1, vim.NIL },
    { 3, sym 'var-name' }, { 3, vim.NIL },
    { 3, sym 'var-name' }, { 3, vim.NIL },
}

describe('buffer', function()
    local lsp_send_stub ---@type busted.stub
    local buffer_onlines_spy ---@type busted.spy
    local bufnr ---@type integer

    setup(function()
        ---@type busted.stub
        lsp_send_stub = stub.new(Lsp, 'send')
        buffer_onlines_spy = spy.on(Buffer, 'on_lines')
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()

        vim.opt_local.autoindent = false
        Buffer.set_mode(bufnr)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'open'))
        assert.False(Lsp.is_running())
        Buffer.apply_colors(1, small_bufcolors, 0, 0)
        assert.are_same(small_extmarks, vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, {}))
    end)

    teardown(function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
        lsp_send_stub:revert()
        buffer_onlines_spy:revert()
    end)

    before_each(function()
        lsp_send_stub:clear()
        buffer_onlines_spy:clear()
    end)

    it('sends complex insertions and replacement', function()
        local testlines = { '    var b = 3; // 🌙 z !', '    var c = 4; // 🤔' }
        local startrow, _ = unpack(vim.api.nvim_win_get_cursor(0))
        vim.cmd({ cmd = 'normal', args = { 'o' .. table.concat(testlines, ' ') } })
        vim.cmd({ cmd = 'normal', args = { '$T!r\n' } })
        assert.wait_called(buffer_onlines_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        local lines = vim.api.nvim_buf_get_lines(bufnr, startrow, startrow + 2, true)
        assert.are_same(testlines, lines)
        assert.True(match_accumulated_changes(lsp_send_stub, { '\n' .. table.concat(testlines, '\n') }, 1))
    end)

    it('sends insertion character-range', function()
        local utf_teststring = '    var a = 2; // 🐰 bunnies🔴🔴 are awesome👀 👍!'
        vim.cmd({ cmd = 'normal', args = { 'o' .. utf_teststring } })
        assert.wait_called(buffer_onlines_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_changes(lsp_send_stub, { '\n' .. utf_teststring }, 0))
    end)

    it('sends correct insertion character-lines', function()
        local utf_teststring = [[    for (Int i = 0; i < 10; i++) {
        print("i = " + i); // ⌨️ :)
    }]]
        vim.cmd({ cmd = 'normal', args = { 'o' .. utf_teststring } })
        assert.wait_called(buffer_onlines_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_changes(lsp_send_stub, { '\n' .. utf_teststring }, 0))
    end)

    it('sends correct replacement character-lines', function()
        local deletedlen = 0
        do -- setup replacement lines
            local utf_teststring = '    var b = 3; // 🌙 z 🤔 !\n    var c = 4;'
            deletedlen = vim.fn.strchars(utf_teststring)
            vim.cmd({ cmd = 'normal', args = { 'o' .. utf_teststring } })
            assert.wait_called(buffer_onlines_spy)
            lsp_send_stub:clear()
            buffer_onlines_spy:clear()
        end
        local replacement = '    var d = 5;'
        vim.cmd({ cmd = 'normal', args = { 'k2S' .. replacement } })
        assert.wait_called(buffer_onlines_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_changes(lsp_send_stub, { replacement, '' }, deletedlen))
    end)

    it('sends correct insertion character-range for empty lines', function()
        local utf_teststring = '\n\n\n'
        vim.cmd({ cmd = 'normal', args = { 'A' .. utf_teststring } })
        assert.wait_called(buffer_onlines_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_changes(lsp_send_stub, { utf_teststring }, 0))
    end)

    it('sends correct deletion character-range for empty lines', function()
        do -- setup empty lines
            vim.cmd({ cmd = 'normal', args = { 'o\n' } })
            assert.wait_called(buffer_onlines_spy)
            lsp_send_stub:clear()
            buffer_onlines_spy:clear()
        end
        vim.cmd({ cmd = 'normal', args = { 'dk' } })
        assert.wait_called(buffer_onlines_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_changes(lsp_send_stub, { '' }, 2))
    end)

    it('sends search+replace', function()
        do -- setup dummy line
            local initial_line = '    foo baz1 foo qux23 foo quux456 foo'
            vim.cmd({ cmd = 'normal', args = { 'o' .. initial_line } })
            assert.wait_called(buffer_onlines_spy)
            assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
            lsp_send_stub:clear()
            buffer_onlines_spy:clear()
        end
        local replacee      = 'foo'
        local replacement   = 'bar🌟'
        local expected_line = '    bar🌟 baz1 bar🌟 qux23 bar🌟 quux456 bar🌟'
        vim.cmd('%s/' .. replacee .. '/' .. replacement .. '/g')
        assert.wait_called(buffer_onlines_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))

        local startrow, _ = unpack(vim.api.nvim_win_get_cursor(0))
        local lines = vim.api.nvim_buf_get_lines(bufnr, startrow - 1, startrow, true)
        assert.are_same({ expected_line }, lines)

        assert.True(match_accumulated_changes(
            lsp_send_stub,
            { replacement, replacement, replacement, replacement },
            string.len(replacee) * 4
        ))
    end)
end)
