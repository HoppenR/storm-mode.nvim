---@diagnostic disable: lowercase-global
-- This file is only used for testing with busted

rockspec_format = "3.0"
package = "storm-mode.nvim"
version = "scm-1"

description = {
    summary = "A Neovim plugin for integrating Storm as an LSP server",
    homepage = 'https://github.com/HoppenR/storm-mode.nvim',
    license = "BSD-2-Clause",
}

dependencies = {
    "lua >= 5.1",
}

test_dependencies = {
    "lua >= 5.1",
    "nlua",
}

source = {
    url = "git+https://github.com/HoppenR/storm-mode.nvim"
}

build = {
    type = "builtin",
}
