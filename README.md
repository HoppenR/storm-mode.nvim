# storm-mode.nvim

# Installation

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
