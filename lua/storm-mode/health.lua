local M = {}

local Config = require('storm-mode.config')

---@return boolean
local function check_compiler()
    if type(Config.compiler) ~= 'string' then
        if type(Config.compiler) == 'nil' then
            vim.health.error('setup compiler path not present')
        else
            vim.health.error('setup compiler path is of wrong type, should be a string')
        end
        return false
    end

    local storm_stat = vim.uv.fs_stat(Config.compiler)
    local is_file = storm_stat and storm_stat.type == 'file' or false
    if not is_file then
        vim.health.warn('setup compiler is not found or not a file')
        return false
    end

    local is_executable = vim.loop.fs_access(Config.compiler, "X")
    if not is_executable then
        vim.health.warn('setup compiler is not an executable file')
        return false
    end
    return true
end

---@return boolean
local function check_root()
    if type(Config.root) ~= 'string' then
        if type(Config.root) == 'nil' then
            vim.health.error('setup root not present')
        else
            vim.health.error('setup root is of wrong type, should be a string')
        end
        return false
    end

    local storm_stat = vim.uv.fs_stat(Config.root)
    local is_file = storm_stat and storm_stat.type == 'directory' or false
    if not is_file then
        vim.health.warn('setup root is not found or not a directory')
        return false
    end
    return true
end

---@return boolean
local function check_highlights()
    if type(Config.highlights) ~= 'table' then
        vim.health.error('setup highlights are not present or not a table')
        return false
    end
    return true
end

M.check = function()
    local bad_config = false
    if package.loaded['storm-mode'] == nil then
        vim.health.error('setup has not been called')
    end
    vim.health.start('Checking for setup configuration errors')
    if not check_compiler() then bad_config = true end
    if not check_root() then bad_config = true end
    if not check_highlights() then bad_config = true end
    if bad_config then
        local msg = 'setup requires a compiler and root path'
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
