# Changelog

## [2.1.0](https://github.com/HoppenR/storm-mode.nvim/compare/v2.0.0...v2.1.0) (2026-11-24)


### Features

* define :Storm and the mappings without setup() ([28da63a](https://github.com/HoppenR/storm-mode.nvim/commit/28da63ad804e90d8ee7498e903dd3a74b16c0bff))
* **nix:** Storm package in nix/storm.nix, plugin defaults to it ([9e97232](https://github.com/HoppenR/storm-mode.nvim/commit/9e9723231e7daa85957fe59dbd9f1c483628127f))


### Bug Fixes

* :Storm errors ignores diagnostics of deleted buffers ([0782d40](https://github.com/HoppenR/storm-mode.nvim/commit/0782d40104a261abf2a0d5f5b5ff290937b293c0))
* setup() changes only the given options ([5d56a5f](https://github.com/HoppenR/storm-mode.nvim/commit/5d56a5fec67ab9c178b8fc71cc29359e8cc07190))
* **test:** open or close the quickfix window together with the list ([837c752](https://github.com/HoppenR/storm-mode.nvim/commit/837c752754b348c8c58be0320c79312a0575cfd6))

## [2.0.0](https://github.com/HoppenR/storm-mode.nvim/compare/v1.2.1...v2.0.0) (2026-11-23)


### ⚠ BREAKING CHANGES

* requires Neovim 0.11 and Storm 0.8.2. Output goes to messages, notifications and diagnostics. The log `:Storm debug show` is gone.

### Features

* storm-mode 2.0 ([6a3beaa](https://github.com/HoppenR/storm-mode.nvim/commit/6a3beaa4bbf557504fdb8547ae6f1385b884b021))

## [1.2.1](https://github.com/HoppenR/storm-mode.nvim/compare/v1.2.0...v1.2.1) (2026-01-17)


### Bug Fixes

* buffer testing ([76ecd58](https://github.com/HoppenR/storm-mode.nvim/commit/76ecd5819a7a5bc80212ea4ccd5100e4f9615725))


### Miscellaneous Chores

* fix versioning after signing commits ([22f8d41](https://github.com/HoppenR/storm-mode.nvim/commit/22f8d41032ce6a9a64eb40c4778c75ae10325cab))
