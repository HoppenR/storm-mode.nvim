---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Turning storm-mode on and off for a buffer, without Storm (stubbed out)
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')
local sym = require('storm-mode.sym').literal

describe('storm-mode', function()
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

    it('set_mode twice does not attach twice', function()
        Buffer.set_mode(bufnr)
        Buffer.set_mode(bufnr)
        local before = Buffer._debug_state(bufnr).last_edit_id
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { 'X' })
        assert.are.equal(before + 1, Buffer._debug_state(bufnr).last_edit_id)
    end)

    it('sets indentexpr, omnifunc and K, and restores them when unset', function()
        vim.bo[bufnr].indentexpr = 'old_indent()'
        vim.bo[bufnr].omnifunc = 'old_omni'
        Buffer.set_mode(bufnr)
        assert.matches('storm%-mode%.buffer', vim.bo[bufnr].indentexpr)
        assert.matches('storm%-mode%.complete', vim.bo[bufnr].omnifunc)
        assert.are.equal('<Plug>(storm-doc-hover)', vim.fn.maparg('K', 'n'))

        Buffer.apply_colors(Buffer.storm_id(bufnr), { { 3, sym 'type-name' } }, 0, 0)
        local colors_ns = vim.api.nvim_get_namespaces()['storm-mode']
        assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(bufnr, colors_ns, 0, -1, {}))
        local running_stub = stub(Lsp, 'is_running').returns(true) -- close is only sent to a running Storm
        Buffer.unset_mode(bufnr)
        running_stub:revert()
        assert.are.equal('old_indent()', vim.bo[bufnr].indentexpr)
        assert.are.equal('old_omni', vim.bo[bufnr].omnifunc)
        assert.are.equal('', vim.fn.maparg('K', 'n'))
        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, colors_ns, 0, -1, {}), 'colors are removed')
        assert.stub(lsp_send_stub).was_called_with(match.is_messagetype(sym 'close'))
    end)

    it('does not override a K mapping the user already has', function()
        vim.keymap.set('n', 'K', '<Nop>', { buffer = bufnr })
        Buffer.set_mode(bufnr)
        Buffer.unset_mode(bufnr)
        assert.are.equal('<Nop>', vim.fn.maparg('K', 'n'))
    end)

    it('indents with tabs shown 4 wide by default, restored when unset', function()
        vim.bo[bufnr].tabstop, vim.bo[bufnr].shiftwidth = 8, 8
        Buffer.set_mode(bufnr)
        assert.are.same({ 4, 4 }, { vim.bo[bufnr].tabstop, vim.bo[bufnr].shiftwidth })
        Buffer.unset_mode(bufnr)
        assert.are.same({ 8, 8 }, { vim.bo[bufnr].tabstop, vim.bo[bufnr].shiftwidth })
    end)

    it('lets FileType autocommands of the user override the indent width', function()
        local group = vim.api.nvim_create_augroup('StormTestFileType', { clear = true })
        vim.api.nvim_create_autocmd('FileType', {
            group = group,
            pattern = 'storm',
            callback = function(args) vim.bo[args.buf].shiftwidth = 2 end,
        })
        Buffer.set_mode(bufnr)
        vim.api.nvim_del_augroup_by_id(group)
        assert.are.equal(2, vim.bo[bufnr].shiftwidth)
    end)

    it('leaves the indent settings alone with indent_width = false', function()
        local Config = require('storm-mode.config')
        rawset(Config, 'indent_width', false) -- shadows the configured value
        vim.bo[bufnr].tabstop, vim.bo[bufnr].shiftwidth = 8, 3
        Buffer.set_mode(bufnr)
        rawset(Config, 'indent_width', nil)
        assert.are.same({ 8, 3 }, { vim.bo[bufnr].tabstop, vim.bo[bufnr].shiftwidth })
    end)

    it('sends the cursor position with open', function()
        vim.api.nvim_win_set_cursor(0, { 2, 4 })
        Buffer.set_mode(bufnr)
        local open
        for _, call in ipairs(lsp_send_stub.calls) do
            if call.vals[1][1] == sym 'open' then open = call.vals[1] end
        end
        assert.is_not_nil(open)
        assert.are.equal(#'Int addTwoNumbers(Int lhs, Int rhs) {\n    ', open[5])
    end)
end)
