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
