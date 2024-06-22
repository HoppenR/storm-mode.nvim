---@diagnostic disable: lowercase-global

rockspec_format = "3.0"
package = "storm-mode"
version = "scm-1"
description = {
    summary = "LSP client for the Storm compiler.",
    detailed = [[
    A plugin that utilizes the storm compiler as an LSP, providing syntax
    highlighting, error checking, and documentation automatically and via simple
    vim commands. For more information see https://storm-lang.org/
    ]],
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
    copy_directories = {},
}
