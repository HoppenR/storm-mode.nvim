---@diagnostic disable: undefined-global
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal
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
    local lsp_send_stub
    local bufnr

    setup(function()
        lsp_send_stub = stub.new(Lsp, 'send')
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()
    end)

    teardown(function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
        lsp_send_stub:revert()
    end)

    it('applies colors', function()
        Buffer.set_mode(bufnr)
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'open'))
        assert.False(Lsp.is_running())
        Buffer.apply_colors(1, small_bufcolors, 0, 0)
        assert.are_same(small_extmarks, vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, {}))
    end)
end)
