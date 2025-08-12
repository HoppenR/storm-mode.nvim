---@diagnostic disable: undefined-global
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

---Collect multiple calls to Buffer.on_change containing contiguous, increasing
---edits into a single string, and compare to an expected string and length
---@alias storm-mode.lsp.message.edit [storm-mode.sym, integer, integer, integer, integer, string]
---@param lsp_send_stub busted.stub
---@param expected string
---@return boolean correct
---@return string? errmsg
local function match_accumulated_edit(lsp_send_stub, expected)
    ---@type {pos: integer, chars: integer, text: string}?
    local insertion = nil
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
        if insertion == nil then
            insertion = { pos = start_pos, chars = chars, text = text_chunk }
        elseif start_pos >= insertion.pos and end_pos <= insertion.pos + insertion.chars then
            insertion = { pos = insertion.pos, chars = insertion.chars + chars, text = insertion.text .. text_chunk }
        else
            return false, ("Multiple disjoint insertions %d..%d and %d..%d")
                :format(insertion.pos, insertion.pos + insertion.chars, start_pos, start_pos + chars)
        end
        ::continue::
    end
    if not insertion then
        return false, "No insertion found"
    end
    if insertion.text ~= expected then
        return false, ('Accumulated text:%q\ndoes not match expected:%q')
            :format(insertion.text, expected)
    end
    local expected_len = vim.fn.strchars(expected)
    if insertion.chars ~= expected_len then
        return false, ('Expected char length mismatch: got %d, expected %d')
            :format(insertion.chars, expected_len)
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
    local buffer_onchange_spy ---@type busted.spy
    local bufnr ---@type integer

    setup(function()
        ---@type busted.stub
        lsp_send_stub = stub.new(Lsp, 'send')
        buffer_onchange_spy = spy.on(Buffer, 'on_change')
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
        buffer_onchange_spy:revert()
    end)

    before_each(function()
        lsp_send_stub:clear()
        buffer_onchange_spy:clear()
    end)

    it('sends correct edit character-range', function()
        local utf_teststring = '    var a = 2; // 🐰 bunnies🔴🔴 are awesome👀 👍!'
        vim.cmd({ cmd = 'normal', args = { 'o' .. utf_teststring } })
        assert.wait_called(buffer_onchange_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_edit(lsp_send_stub, '\n' .. utf_teststring))
    end)

    it('sends correct edit character-range 2', function()
        local utf_teststring = [[    for (Int i = 0; i < 10; i++) {
        print("i = " + i); // ⌨️
    }]]
        vim.cmd({ cmd = 'normal', args = { 'o' .. utf_teststring } })
        assert.wait_called(buffer_onchange_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_edit(lsp_send_stub, '\n' .. utf_teststring))
    end)

    it('sends correct edit range for empty lines', function()
        local utf_teststring = '\n\n\n'
        vim.cmd({ cmd = 'normal', args = { 'A' .. utf_teststring } })
        assert.wait_called(buffer_onchange_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_edit(lsp_send_stub, utf_teststring))
    end)

    it('correctly deletes empty lines', function()
        do -- setup empty lines
            vim.cmd({ cmd = 'normal', args = { 'o\n' } })
            assert.wait_called(buffer_onchange_spy)
            lsp_send_stub:clear()
            buffer_onchange_spy:clear()
        end
        vim.cmd({ cmd = 'normal', args = { 'dk' } })
        assert.wait_called(buffer_onchange_spy)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_edit(lsp_send_stub, ''))
    end)
end)
