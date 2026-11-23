<div align="center">

[![Header](./assets/storm-mode-header.png)](https://github.com/HoppenR/storm-mode.nvim)

[![Neovim](https://img.shields.io/badge/Neovim-0.11+-cornflowerblue?style=for-the-badge)](https://neovim.io)
[![LuaRocks](https://img.shields.io/luarocks/v/HoppenR/storm-mode.nvim?color=darkgreen&style=for-the-badge)](https://luarocks.org/modules/HoppenR/storm-mode.nvim)
[![License](https://img.shields.io/badge/license-BSD--2--Clause-black?style=for-the-badge)](./LICENSE)

</div>

## - Introduction - :cloud_with_lightning:

**`storm-mode.nvim`** is a neovim plugin built for utilizing the built-in LSP
features in the [Storm](https://storm-lang.org/) compiler.

It provides the following features, right in your Neovim editor!
- Syntax highlighting.
- Indentation and paragraph navigation (`}`).
- Name completion with `<C-x><C-o>`.
- Documentation for all languages in Storm:
-- `K` for a floating window,
-- `:Storm doc` for a split, with links to types, members and source.
- Evaluating expressions, running functions and reloading code in the running
  Storm process.
- Errors as diagnostics (syntax errors while you type, type errors from
  running code), and in the quickfix list with `:Storm errors`.
- Debugging output.
- Lazy-loading user-commands and `<Plug>` mappings.

## - Requirements - :memo:

- Up to date version of [**`Neovim`**](https://neovim.io/), v0.11.0 or newer!
- [**`Storm`**](https://storm-lang.org/Downloads/index.html) 0.8.2 or newer.
  Distribution packages can be older (Ubuntu 24.04 ships 0.6.20); with Nix,
  `nix build .#storm-lang` builds a supported version.
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
    -- opts = { ... }, -- options, see :help storm-mode.setup()
},
```

</details>

<details>
<summary>Nix (Home Manager)</summary>

The flake's package defaults to the Storm it builds, so no setup is needed:

```nix
# inputs.storm-mode-nvim.url = "github:HoppenR/storm-mode.nvim";
programs.neovim.plugins = [
  storm-mode-nvim.packages.${pkgs.stdenv.hostPlatform.system}.storm-mode-nvim
];
```

Storm is built from source; to download it prebuilt instead, add the cache:

```nix
nix.settings = {
  extra-substituters = [ "https://storm-mode.cachix.org" ];
  extra-trusted-public-keys = [
    "storm-mode.cachix.org-1:GlhdGSxxBzQVaOsJEtXQCGOf3mPocPFe2vZSVql1G3E="
  ];
};
```

</details>

> [!IMPORTANT]
> `storm-mode.nvim` requires Storm to be installed on the system. Calling
> `require('storm-mode').setup()` is optional; it's needed if Storm is
> installed somewhere other than `/usr/bin/storm` and `/usr/lib/storm/`, or
> to change other options.
>
> See [**the documentation**](./doc/storm-mode.txt) for
> more info and examples on how to set up `storm-mode.nvim`.

## - Troubleshooting - :mag:

The `:checkhealth storm-mode` command can help troubleshoot configuration
issues.

If names from your own files don't complete or resolve, or `:Storm run` can't
find your functions, the files aren't in a package Storm knows. Add the
project with the `include` option, for example from a per-project
`.nvim.lua`: see `:help storm-mode.packages`.

## - Usage - :books:

Run `:Storm start` in a buffer, or `:Storm global` to use storm-mode for all
supported files. See `:help storm-mode` for the commands, options and
`<Plug>` mappings.

## - Testing - :test_tube:

The tests run against a real Storm. With Nix, everything is provided:
```bash
nix develop --command busted
```
Otherwise, point the tests at your Storm and run `busted`:
```bash
export STORM_COMPILER="~/projects/storm-lang/storm"
export STORM_ROOT="~/projects/storm-lang/root/"
busted
```

## - License - :balance_scale:

`storm-mode.nvim` is free software and uses the same `BSD-2-Clause` license as
Storm.
