# storm-mode.nvim

storm-mode.nvim is an LSP client for the Storm compiler. It is free
software and uses the same license as Storm.

## Requirements

- Neovim >= 0.5.0

## Installation

Lazy.nvim:
```lua
return {
    'HoppenR/storm-mode.nvim',
    opts = {
        compiler = vim.fs.normalize('~/projects/storm-lang/storm'),
        root = vim.fs.normalize('~/projects/storm-lang/root/'),
    },
},
```

## Feature progress

Client -> Lsp
- [x] quit (`:StormQuit`)
- [x] supported
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
- [x] supported
- [x] color
- [ ] indent
- [ ] complete-name
- [ ] documentation
