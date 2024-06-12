# storm-mode.nvim

## Requirements

- Neovim >v0.5.0
- love11.4, jit2.1
- Plenary.nvim (only for testing!)

## Testing

Run `:PlenaryBustedFile tests/storm-mode.lua` from the project root directory.

## Installation

Lazy.nvim:
```lua
return {
    'HoppenR/storm_mode.nvim',
    opts = {
        compiler = vim.fn.expand('~/projects/storm-lang/storm'),
        root = vim.fn.expand('~/projects/storm-lang/root/'),
    },
},
```
