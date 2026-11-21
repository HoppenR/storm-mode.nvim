---@diagnostic disable: undefined-global, undefined-field, need-check-nil, param-type-mismatch, missing-parameter, duplicate-set-field, missing-fields
-- Dotted pairs decode to arrays with a `tail` field, e.g. { "a", tail = "b" }
--# selene: allow(mixed_table)
local Doc = require('storm-mode.doc')
local Lsp = require('storm-mode.lsp')

-- Reply for (documentation "core.print" ...) recorded from Storm 0.8.2
local print_doc = {
    'print',
    { { 's', 'core.Str', 'core.Str', vim.NIL } },
    { { '->', 'void', vim.NIL, vim.NIL }, { 'on', 'core.Compiler', 'core.Compiler', vim.NIL } },
    { 'core.lang.Public', tail = 'public' },
    'Quick print line function.',
    { 'source for compiler:Compiler/Lib/Io.h', 242, 243 },
    vim.NIL,
}
local str_doc = {
    'Str',
    vim.NIL,
    { { 'extends', 'core.Object', 'core.Object', vim.NIL } },
    { 'core.lang.Public', tail = 'public' },
    'The string type used in Storm.\n\nStrings are immutable.',
    vim.NIL,
    {
        {
            'Members',
            { 'core.Str.+(core.Str, core.Str)', tail = '+(core.Str, core.Str) -> core.Str' },
            { 'core.Str.any(core.Str)', tail = 'any(core.Str) -> core.Bool' },
        },
    },
}

local function wait(cond, ms) return vim.wait(ms or 3000, cond, 20) end

---Link at the first occurrence of `text` in the rendered builder
local function link_for(b, text)
    for _, link in ipairs(b.links) do
        if b.lines[link.row + 1]:sub(link.col + 1, link.end_col) == text then return link end
    end
end

describe('documentation rendering', function()
    it('renders signature, notes, position and body like the Emacs plugin', function()
        local b = Doc.render({ print_doc })
        assert.are.same({
            'public print(core.Str s) -> void, on core.Compiler:',
            '',
            'At: source for compiler:Compiler/Lib/Io.h(242-243)',
            '',
            'Quick print line function.',
        }, b.lines)
        assert.are.same({ name = 'core.Str' }, link_for(b, 'core.Str').target)
        assert.are.same({ name = 'core.lang.Public' }, link_for(b, 'public').target)
        assert.are.same(
            { file = 'source for compiler:Compiler/Lib/Io.h', offset = 242 },
            link_for(b, 'source for compiler:Compiler/Lib/Io.h(242-243)').target
        )
    end)

    it('renders references as links to their full names', function()
        local b = Doc.render({ str_doc })
        assert.are.same({
            'public Str extends core.Object:',
            '',
            'The string type used in Storm.',
            '',
            'Strings are immutable.',
            '',
            'Members:',
            '  +(core.Str, core.Str) -> core.Str',
            '  any(core.Str) -> core.Bool',
        }, b.lines)
        assert.are.same({ name = 'core.Str.any(core.Str)' }, link_for(b, 'any(core.Str) -> core.Bool').target)
    end)

    it('adds back/forward links from the history', function()
        local view = { history = { {}, {}, {} }, index = 2 }
        local b = Doc.render({ print_doc }, view)
        assert.are.equal('[back]  [forward]', b.lines[#b.lines])
        assert.are.same({ nav = 'forward' }, link_for(b, '[forward]').target)
    end)
end)

describe('documentation from Storm', function()
    local bufnr

    setup(function()
        -- The demo package, for documentation with a source position
        require('storm-mode').setup({
            compiler = os.getenv('STORM_COMPILER'),
            root = os.getenv('STORM_ROOT'),
            include = { { path = 'spec/test_data/demo', package = 'demo' } },
        })
        vim.cmd.edit('spec/test_data/small_source.bs')
        bufnr = vim.api.nvim_get_current_buf()
        vim.cmd.Storm('start')
    end)

    teardown(function()
        vim.cmd('silent! only')
        vim.cmd.Storm('quit')
        wait(function() return not Lsp.is_running() end)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        require('storm-mode').setup({ compiler = os.getenv('STORM_COMPILER'), root = os.getenv('STORM_ROOT') })
    end)

    before_each(function()
        vim.cmd('silent! only')
        vim.api.nvim_set_current_buf(bufnr)
    end)

    it('queries documentation', function()
        local docs = Doc.query('core.print', vim.fn.getcwd())
        assert.are.equal('print', docs[1][1])
        assert.are.same({}, Doc.query('doesNotExist', vim.fn.getcwd()))
    end)

    it(':Storm doc opens a split; links and history work', function()
        vim.cmd.Storm({ 'doc', 'core.print' })
        local doc_buf = vim.api.nvim_get_current_buf()
        assert.are.equal('storm-doc', vim.bo[doc_buf].filetype)
        assert.are.equal(
            'public print(core.Str s) -> void, on core.Compiler:',
            vim.api.nvim_buf_get_lines(doc_buf, 0, 1, false)[1]
        )

        -- Follow the core.Str link
        vim.api.nvim_win_set_cursor(0, { 1, #'public print(' + 2 })
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.matches('^public Str', vim.api.nvim_buf_get_lines(doc_buf, 0, 1, false)[1])
        assert.matches('%[back%]', table.concat(vim.api.nvim_buf_get_lines(doc_buf, 0, -1, false), '\n'))

        vim.api.nvim_feedkeys(vim.keycode('<C-o>'), 'x', false)
        assert.matches('^public print', vim.api.nvim_buf_get_lines(doc_buf, 0, 1, false)[1])
        vim.api.nvim_feedkeys(vim.keycode('<C-i>'), 'x', false)
        assert.matches('^public Str', vim.api.nvim_buf_get_lines(doc_buf, 0, 1, false)[1])

        -- A second :Storm doc reuses the split
        local windows = #vim.api.nvim_list_wins()
        vim.cmd('wincmd p')
        vim.cmd.Storm({ 'doc', 'core.Int' })
        assert.are.equal(windows, #vim.api.nvim_list_wins())
    end)

    it('K opens a floating window for the name under the cursor', function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'core.print("x");' })
        vim.api.nvim_win_set_cursor(0, { 1, 6 })
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_feedkeys('K', 'x', false)
        local float = Doc._float()
        assert.is_not_nil(float)
        assert.are_not.equal('', vim.api.nvim_win_get_config(float.win).relative, 'is a floating window')
        assert.matches('^public print', vim.api.nvim_buf_get_lines(float.buf, 0, 1, false)[1])
        assert.are.equal(source_win, vim.api.nvim_get_current_win(), 'focus stays in the source')

        -- K again enters the float, moving the cursor in the source closes it
        vim.api.nvim_feedkeys('K', 'x', false)
        assert.are.equal(float.win, vim.api.nvim_get_current_win())
        vim.api.nvim_set_current_win(source_win)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.api.nvim_exec_autocmds('CursorMoved', { buffer = bufnr })
        assert.is_false(vim.api.nvim_win_is_valid(float.win))
        vim.cmd('silent! undo')
    end)

    it('links to the source position, also in a loaded and modified file', function()
        vim.cmd.edit('spec/test_data/demo/main.bs')
        local main = vim.api.nvim_get_current_buf()
        vim.cmd.Storm('start')
        vim.api.nvim_buf_set_lines(main, -1, -1, false, { '' }) -- modified: following must not fail (E37)
        vim.cmd.Storm({ 'doc', 'demo.answer' })
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local row = vim.iter(ipairs(lines)):find(function(_, l) return l:match('^At: ') end)
        assert.is_not_nil(row, 'documentation has a source position')
        vim.api.nvim_win_set_cursor(0, { row, 5 })
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.are.equal(main, vim.api.nvim_get_current_buf())
        assert.matches('answer', vim.api.nvim_get_current_line())
        vim.cmd('silent! only')
        vim.api.nvim_buf_delete(main, { force = true })
    end)

    it('warns when there is no documentation', function()
        local notify_stub = stub.new(vim, 'notify')
        vim.cmd.Storm({ 'doc', 'doesNotExist' })
        notify_stub:revert()
        assert.stub(notify_stub).was_called_with(match.matches('no documentation'), vim.log.levels.WARN)
    end)
end)
