local M = {}

local Config = require('storm-mode.config')

---@return boolean
local function check_compiler()
    if type(Config.compiler) ~= 'string' then
        if type(Config.compiler) == 'nil' then
            vim.health.error('storm compiler path not supplied')
        else
            vim.health.error('storm compiler path is of wrong type, should be a string')
        end
        return false
    end

    local storm_stat = vim.uv.fs_stat(Config.compiler)
    local is_file = storm_stat and storm_stat.type == 'file' or false
    if not is_file then
        vim.health.warn('storm compiler is not found or not a file')
        return false
    end

    local is_executable = vim.loop.fs_access(Config.compiler, "X")
    if not is_executable then
        vim.health.warn('storm compiler is not an executable file')
        return false
    end
    return true
end

---@return boolean
local function check_root()
    if type(Config.root) ~= 'string' then
        if type(Config.root) == 'nil' then
            vim.health.error('storm root path not supplied')
        else
            vim.health.error('storm root path is of wrong type, should be a string')
        end
        return false
    end

    local storm_stat = vim.uv.fs_stat(Config.root)
    local is_file = storm_stat and storm_stat.type == 'directory' or false
    if not is_file then
        vim.health.warn('storm root is not found or not a directory')
        return false
    end
    return true
end

---@return boolean
local function check_highlights()
    if type(Config.highlights) ~= 'table' then
        vim.health.error('storm-mode highlights are of wrong type, should be a table')
        return false
    end
    return true
end

M.check = function()
    local bad_config = false
    vim.health.start('Checking for configuration errors')
    if not check_compiler() then bad_config = true end
    if not check_root() then bad_config = true end
    if not check_highlights() then bad_config = true end
    if bad_config then
        local msg = 'storm-mode requires a compiler and root path'
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
