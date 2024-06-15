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

## Feature progress

Client -> Lsp
- [x] quit (`:StormQuit`)
- [ ] supported
- [x] open (`:StormMode`)
- [x] close (`:StormClose`)
- [ ] edit
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
