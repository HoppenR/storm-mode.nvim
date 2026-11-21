local M = {}

local Config = require('storm-mode.config')

---@return boolean
function M._check_compiler()
    local storm_stat = vim.uv.fs_stat(Config.compiler)
    local is_file = storm_stat and storm_stat.type == 'file' or false
    if not is_file then
        vim.health.warn('compiler is not found or not a file')
        return false
    end

    local is_executable = vim.uv.fs_access(Config.compiler, 'X')
    if not is_executable then
        vim.health.warn('compiler is not an executable file')
        return false
    end
    return true
end

---@return boolean
function M._check_root()
    local storm_stat = vim.uv.fs_stat(Config.root)
    local is_file = storm_stat and storm_stat.type == 'directory' or false
    if not is_file then
        vim.health.warn('root path is not found or not a directory')
        return false
    end
    return true
end

---@return boolean
function M._check_include()
    local ok = true
    for _, inc in ipairs(Config.include) do
        local stat = vim.uv.fs_stat(vim.fn.fnamemodify(inc.path, ':p'))
        if not stat or stat.type ~= 'directory' then
            vim.health.warn(string.format('include path for package %s is not a directory: %s', inc.package, inc.path))
            ok = false
        end
    end
    return ok
end

function M.check()
    vim.health.start('Checking the Neovim version')
    if vim.fn.has('nvim-0.11') == 1 then
        vim.health.ok('Neovim 0.11 or newer')
    else
        vim.health.error('storm-mode.nvim requires Neovim 0.11 or newer')
    end

    vim.health.start('Checking if the plugin has been loaded')
    if package.loaded['storm-mode'] == nil then
        vim.health.error('The plugin has not been loaded')
    else
        vim.health.ok('The plugin has been loaded')
    end

    vim.health.start('Checking for setup configuration errors')
    if not M._check_compiler() or not M._check_root() then
        local msg = 'setup requires a correct compiler and root path'
        local setup_advice = {
            'require("storm-mode").setup({',
            '    compiler = "/path/to/storm",',
            '    root = "/path/to/storm-root/",',
            '})',
        }
        vim.health.warn(msg, setup_advice)
    else
        vim.health.ok('No errors found in config')
    end

    vim.health.start('Checking include paths')
    if #Config.include == 0 then
        vim.health.info('No include paths configured')
    elseif M._check_include() then
        vim.health.ok('All include paths exist')
    end

    vim.health.start('Storm process')
    if require('storm-mode.lsp').is_running() then
        vim.health.ok('Storm is running: ' .. table.concat(require('storm-mode.lsp').compiler_args(), ' '))
    else
        vim.health.info('Storm is not running')
    end
end

return M
