vim.opt.runtimepath:append(vim.env.STORM_MODE_NVIM_HOME)
StormMode = require('storm-mode')

StormMode.setup({
    compiler = vim.env.STORM_COMPILER,
    root = vim.env.STORM_ROOT,
    -- The demo package used by the tests, so :Storm run works in
    -- spec/test_data/demo/main.bs
    include = {
        { path = vim.env.STORM_MODE_NVIM_HOME .. '/spec/test_data/demo', package = 'demo' },
    },
})

-- Keymaps for storm-mode buffers, modelled on the Emacs plugin's C-c bindings
-- (C-c h → <localleader>h, C-c d c → <localleader>dc, ...). storm-mode sets
-- 'filetype' to storm, and maps K to the documentation float by itself.
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'storm',
    group = vim.api.nvim_create_augroup('StormModeDevKeymaps', { clear = true }),
    callback = function(args)
        local function map(modes, lhs, plug, desc)
            vim.keymap.set(modes, lhs, '<Plug>(' .. plug .. ')', { buffer = args.buf, desc = desc })
        end
        vim.g.maplocalleader = [[\]]
        map('n', '<localleader>h', 'storm-doc', 'Storm: documentation (split)')
        map({ 'n', 'x' }, '<localleader>e', 'storm-eval', 'Storm: evaluate')
        map('n', '<localleader>r', 'storm-run-cursor', 'Storm: run function at cursor')
        map('n', '<localleader>R', 'storm-run-all', 'Storm: run all functions')
        map('n', '<localleader>u', 'storm-reload', 'Storm: reload buffer')
        map('n', '<localleader>U', 'storm-reload-package', 'Storm: reload package')
        map('n', '<localleader>q', 'storm-errors', 'Storm: errors in the quickfix list')
        map('n', '<localleader>dc', 'storm-debug-content', 'Storm: debug content')
        map('n', '<localleader>dt', 'storm-debug-tree', 'Storm: debug tree')
        map('n', '<localleader>du', 'storm-debug-recolor', 'Storm: recolor')
        map('n', '<localleader>dx', 'storm-debug-uncolor', 'Storm: remove colors')
        map('n', '<localleader>do', 'storm-debug-reopen', 'Storm: re-open buffer')
        map('n', '<localleader>de', 'storm-debug-error', 'Storm: show first error')
    end,
})
