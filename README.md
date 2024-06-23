<div align="center">

[![Header](./assets/storm-mode-header.png)](https://github.com/HoppenR/storm-mode.nvim)

[![Neovim](https://img.shields.io/badge/Neovim-0.8+-cornflowerblue?style=for-the-badge)](https://neovim.io)
[![LuaRocks](https://img.shields.io/luarocks/v/HoppenR/storm-mode.nvim?color=darkgreen&style=for-the-badge)](https://luarocks.org/modules/HoppenR/storm-mode.nvim)
[![License](https://img.shields.io/badge/license-BSD--2--Clause-black?style=for-the-badge)](./LICENSE)

</div>

## - Introduction - :cloud_with_lightning:

**`storm-mode.nvim`** is a neovim plugin built for utilizing the built-in LSP
features in the [Storm](https://storm-lang.org/) compiler.

It provides the following features, right in your Neovim editor!
- Syntax highlighting.
- Debugging output.
- Documentation for all languages in Storm.
- Lazy-loading user-commands.

## - Requirements - :memo:

- [**`Neovim`**](https://neovim.io/) v0.8.0 or newer!
- [**`Storm binary release`**](https://storm-lang.org/Downloads/index.html)
- [**`busted`**](https://lunarmodules.github.io/busted/) and
  [**`nlua`**](https://github.com/mfussenegger/nlua) (for testing!)

## - Installation - :package:

Use your favorite method of installation.

<details open>
<summary>Rocks.nvim</summary>

Run `:Rocks install storm-mode.nvim`.

</details>

<details>
<summary>Lazy.nvim</summary>

```lua
return {
    'HoppenR/storm-mode.nvim',
    lazy = false, -- first load only exposes lazy-loading user-commands
    opts = {
        compiler = vim.fs.normalize('~/projects/storm-lang/storm'),
        root = vim.fs.normalize('~/projects/storm-lang/root/'),
    },
},
```

</details>

> [!IMPORTANT]
> `storm-mode.nvim` requires a downloaded and unpacked binary release of
> Storm as well as the following two configuration options.
>
> These options tell the plugin where the Storm files are located.
> - path to the Storm compiler.
> - path to the Storm root directory.
>
> See [**the documentation**](./doc/storm-mode.txt) for
> more info and examples on how to set up `storm-mode.nvim`.

## - Troubleshooting - :mag:

The `:checkhealth storm-mode` command can help troubleshoot configuration
issues.

## - Feature progress - :building_construction:

- [x] Global mode - `:Storm global`
- [ ] Dedicated output window, similar to the \*compilation\* buffer in Emacs.

#### Supported `Client -> Lsp` messages

- [x] quit - `:Storm quit`
- [x] supported
- [x] open - `:Storm start`
- [x] close - `:Storm close`
- [x] edit (partial, desyncs can happen but usually catches up eventually)
- [x] point
- [ ] indent
- [x] color - `:Storm debug recolor`
- [ ] complete-name
- [ ] documentation
- [x] debug tree - `:Storm debug tree`
- [x] debug content - `:Storm debug content`
- [x] error - `:Storm debug error`

#### Supported `Lsp -> Client` messages

- [x] supported
- [x] color
- [ ] indent
- [ ] complete-name
- [ ] documentation

## - License - :balance_scale:

`storm-mode.nvim` is free software and uses the same `BSD-2-Clause` license as
Storm.
