---@diagnostic disable: undefined-global
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

---@alias storm-mode.lsp.message.edit [storm-mode.sym, integer, integer, integer, integer, string]
---@param lsp_send_stub busted.stub
---@param expected_full_text string
---@param expected_len integer
---@return boolean, string?
local function match_accumulated_edit(lsp_send_stub, expected_full_text, expected_len)
    local accumulated_text = ''
    local last_end = nil
    local first_start = nil
    for i = 1, #lsp_send_stub.calls do
        local vals = lsp_send_stub.calls[i].vals[1]
        local type = vals[1]
        if type ~= sym 'edit' then
            goto continue
        end
        ---@cast vals storm-mode.lsp.message.edit
        local start_pos = vals[4]
        local end_pos = vals[5]
        local text_chunk = vals[6]
        if not first_start then
            first_start = start_pos
        end
        if last_end ~= nil and start_pos ~= last_end then
            return false, ('Call %d - start %d does not continue from %d'):format(i, start_pos, last_end)
        end
        accumulated_text = accumulated_text .. text_chunk
        last_end = end_pos + vim.fn.strchars(text_chunk)
        ::continue::
    end
    if accumulated_text ~= expected_full_text then
        return false, ('Accumulated text:%q\ndoes not match expected:%q'):format(accumulated_text, expected_full_text)
    end
    if last_end - first_start ~= expected_len then
        return false, ('Expected char length mismatch: got %d, expected %d'):format(last_end - first_start, expected_len)
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

    -- TODO: Also test insertions before AND after an existing mbyte
    it('sends correct edit character range', function()
        local utf_teststring = [[
            var a = 2; // 🐰 bunnies🔴🔴🔴🔴🔴🔴 are awesome!👀 👍👍s dh'
        ]]
        local teststring_utflen = vim.fn.strchars(utf_teststring)
        vim.cmd({ cmd = 'normal', args = { 'A' .. utf_teststring } })
        assert.wait_called(buffer_onchange_spy)

        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_edit(lsp_send_stub, utf_teststring, teststring_utflen))
    end)

    it('correctly deletes an empty line', function()
        vim.cmd({ cmd = 'normal', args = { 'o' } })
        assert.wait_called(buffer_onchange_spy)
        lsp_send_stub:clear()
        buffer_onchange_spy:clear()

        vim.cmd({ cmd = 'normal', args = { 'dd' } })
        assert.wait_called(buffer_onchange_spy)

        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'edit'))
        assert.True(match_accumulated_edit(lsp_send_stub, '', 1))
    end)
end)
