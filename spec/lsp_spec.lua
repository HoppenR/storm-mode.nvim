---@module "busted"

describe('lsp', function()
    require('storm-mode')
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.cmd[[
    edit ../data/small_source.bs
    Storm start
    ]]
    os.execute('sleep 0.2')
    print(require('storm-mode.lsp').is_running())
    vim.cmd[[
    Storm quit
    ]]
end)
