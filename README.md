# storm-mode.nvim

## Requirements

- Neovim >= 0.5.0

## Installation

Lazy.nvim:
```lua
return {
    'HoppenR/storm-mode.nvim',
    opts = {
        compiler = vim.fn.expand('~/projects/storm-lang/storm'),
        root = vim.fn.expand('~/projects/storm-lang/root/'),
    },
},
```

## Differences

This plugin is a bit more opinionated than the original `storm-mode.el`. It sets
autocommands to start the compiler upon first buffer entry to a storm file, and
using `:StormQuit` unloads all the relevant buffers from nvim.

## Feature progress

Client -> Lsp
- [x] quit (`:StormQuit`)
- [ ] supported
- [x] open
- [x] close
- [x] edit (partial, desyncs can happen but usually catches up eventually)
- [ ] point
- [ ] indent
- [x] color (`:StormDebugReColor`)
- [ ] complete-name
- [ ] documentation
- [ ] debug tree (secret, arg = { sbufid, nil })
- [ ] debug content (secret, arg = { sbufid })
- [ ] error (secret, arg = { sbufid })

Lsp -> Client
- [ ] supported
- [x] color (auto)
- [ ] indent
- [ ] complete-name
- [ ] documentation
