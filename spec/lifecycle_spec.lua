---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Storm restarting or crashing while buffers are in storm-mode
local Buffer = require('storm-mode.buffer')
local Lsp = require('storm-mode.lsp')

local function wait(cond, ms) return vim.wait(ms or StormTest.TIMEOUT_MS, cond, 20) end
local function read_buffer(bufnr) return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n' end

describe('Storm lifecycle', function()
    local bufnr, orig_apply_colors, color_calls

    ---Wait for a color message for the latest edit id
    local function wait_colors()
        local id = Buffer._debug_state(bufnr).last_edit_id
        return wait(function()
            for _, call in ipairs(color_calls) do
                if call.id == id and call.n > 0 then return true end
            end
            return false
        end)
    end

    setup(function()
        orig_apply_colors = Buffer.apply_colors
        Buffer.apply_colors = function(sbufnr, colors, edit_id, start_ch)
            table.insert(color_calls, { id = edit_id, n = #colors })
            return orig_apply_colors(sbufnr, colors, edit_id, start_ch)
        end
    end)

    teardown(function() Buffer.apply_colors = orig_apply_colors end)

    before_each(function()
        color_calls = {}
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()
        vim.cmd.Storm('start')
        assert.is_true(wait_colors())
    end)

    after_each(function()
        vim.cmd.Storm('quit')
        wait(function() return not Lsp.is_running() end)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it(':Storm restart re-opens storm-mode buffers', function()
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { ' ' })
        assert.are.equal(1, Buffer._debug_state(bufnr).last_edit_id)
        local old_handle = Lsp.lsp_handle
        vim.cmd.Storm('restart')
        assert.is_true(wait(function() return Lsp.is_running() and Lsp.lsp_handle ~= old_handle end))

        local state = Buffer._debug_state(bufnr)
        assert.are.equal(0, state.last_edit_id, 'buffer was re-opened')
        assert.are.equal(read_buffer(bufnr), state.content)
        color_calls = {}
        assert.is_true(wait_colors(), 'Storm colors the re-opened buffer')

        vim.api.nvim_buf_set_text(bufnr, 1, 0, 1, 0, { ' ' })
        assert.is_true(wait_colors(), 'edits work after the restart')
    end)

    it('warns when Storm exits unexpectedly and re-opens buffers on the next edit', function()
        local notify_stub = stub.new(vim, 'notify')
        Lsp.lsp_handle:kill('sigkill')
        assert.is_true(wait(function() return not Lsp.is_running() and Lsp.lsp_handle == nil end))
        notify_stub:revert()
        assert.stub(notify_stub).was_called_with(match.matches('exited unexpectedly'), vim.log.levels.WARN)

        color_calls = {}
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { ' ' })
        assert.is_true(wait(function() return Lsp.is_running() end))
        local state = Buffer._debug_state(bufnr)
        assert.are.equal(read_buffer(bufnr), state.content)
        assert.are.equal(0, state.last_edit_id, 'the edit was sent as part of the re-opened buffer')
        assert.is_true(wait_colors())
    end)

    it('fires User StormStarted and StormStopped', function()
        local events = {}
        local group = vim.api.nvim_create_augroup('StormTestEvents', { clear = true })
        vim.api.nvim_create_autocmd('User', {
            group = group,
            pattern = { 'StormStarted', 'StormStopped' },
            callback = function(args) table.insert(events, { args.match, args.data }) end,
        })
        vim.cmd.Storm('restart')
        assert.is_true(wait(function() return #events == 2 end))
        assert.are.same({ 'StormStopped', { code = 0, signal = 0, expected = true } }, events[1])
        assert.are.equal('StormStarted', events[2][1])

        events = {}
        Lsp.lsp_handle:kill('sigkill')
        assert.is_true(wait(function() return #events == 1 end))
        vim.api.nvim_del_augroup_by_id(group)
        assert.are.equal('StormStopped', events[1][1])
        assert.is_false(events[1][2].expected)
    end)

    it(':Storm restart! writes modified buffers first', function()
        local file = vim.fn.tempname() .. '.bs'
        vim.fn.writefile({ 'old' }, file)
        vim.cmd.edit(file)
        local other = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(other, 0, -1, false, { 'new' })
        vim.cmd.Storm({ 'restart!' })
        assert.are.same({ 'new' }, vim.fn.readfile(file))
        assert.is_false(vim.bo[other].modified)
        vim.api.nvim_buf_delete(other, { force = true })
        vim.api.nvim_set_current_buf(bufnr)
    end)

    it(':Storm debug reopen sends the buffer again', function()
        vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { ' ' })
        assert.are.equal(1, Buffer._debug_state(bufnr).last_edit_id)
        color_calls = {}
        vim.cmd.Storm({ 'debug', 'reopen' })
        assert.are.equal(0, Buffer._debug_state(bufnr).last_edit_id)
        assert.is_true(wait_colors())
    end)

    it(':Storm quit stops Storm without a warning, showing its farewell', function()
        local out = StormTest.record()
        vim.cmd.Storm('quit')
        assert.is_true(wait(function() return Lsp.lsp_handle == nil end))
        out.restore()
        -- A notification about the file opened in before_each may arrive meanwhile
        local farewell = vim.tbl_filter(function(n) return n.msg == 'Storm: Terminating. Bye!' end, out.notifications)
        assert.are.same({ { msg = 'Storm: Terminating. Bye!', level = vim.log.levels.INFO } }, farewell)
        assert.is_nil(out.text():find('unexpectedly'))
    end)

    it('shows Storm starting and opening files', function()
        local out = StormTest.record()
        vim.cmd.Storm('restart')
        -- The new process starts, then re-opens the buffer (a notification about
        -- the open in before_each may arrive first)
        local ok = wait(function()
            local text = out.text()
            local started = text:find('Storm: Language server started%.')
            return started ~= nil and text:find('Opened small_source%.bs in', started) ~= nil
        end)
        out.restore()
        assert.is_true(ok, out.text())
    end)
end)
