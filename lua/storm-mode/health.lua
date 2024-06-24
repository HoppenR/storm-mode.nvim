local M = {}

local Config = require('storm-mode.config')

---@return boolean
local function check_compiler()
    local storm_stat = vim.uv.fs_stat(Config.compiler)
    local is_file = storm_stat and storm_stat.type == 'file' or false
    if not is_file then
        vim.health.warn('compiler is not found or not a file')
        return false
    end

    local is_executable = vim.uv.fs_access(Config.compiler, "X")
    if not is_executable then
        vim.health.warn('compiler is not an executable file')
        return false
    end
    return true
end

---@return boolean
local function check_root()
    local storm_stat = vim.uv.fs_stat(Config.root)
    local is_file = storm_stat and storm_stat.type == 'directory' or false
    if not is_file then
        vim.health.warn('root path is not found or not a directory')
        return false
    end
    return true
end

M.check = function()
    vim.health.start('Checking if the plugin has been loaded')
    if package.loaded['storm-mode'] == nil then
        vim.health.error('The plugin has not been loaded')
    else
        vim.health.ok('The plugin has been loaded')
    end

    vim.health.start('Checking for setup configuration errors')
    if not check_compiler() or not check_root() then
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
end

return M
