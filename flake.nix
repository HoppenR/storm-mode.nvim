{
  description = "storm-mode.nvim: Neovim plugin for Storm";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  nixConfig = {
    extra-substituters = [ "https://storm-mode.cachix.org" ];
    extra-trusted-public-keys = [
      "storm-mode.cachix.org-1:GlhdGSxxBzQVaOsJEtXQCGOf3mPocPFe2vZSVql1G3E="
    ];
  };

  outputs =
    { nixpkgs, ... }:
    let
      storm-mode-nvim =
        {
          lib,
          vimUtils,
          neovim-unwrapped,
          luajitPackages,
          storm-lang,
        }:
        let
          fs = lib.fileset;
          # buildVimPlugin generates doc/tags (vimGenDocHook runs :helptags on $out/doc)
          pluginSrc = fs.toSource {
            root = ./.;
            fileset = fs.unions [
              ./lua
              ./plugin
              ./doc
              ./README.md
              ./LICENSE
            ];
          };
          # Tests, copied in for the checkPhase only
          testSrc = fs.toSource {
            root = ./.;
            fileset = fs.unions [
              ./spec
              ./.busted
            ];
          };
        in
        vimUtils.buildVimPlugin {
          pname = "storm-mode.nvim";
          version = "2.0.0"; # x-release-please-version
          src = pluginSrc;

          postPatch = /* bash */ ''
            substituteInPlace lua/storm-mode/config.lua \
              --replace-fail "compiler = '/usr/bin/storm'" "compiler = '${lib.getExe storm-lang}'" \
              --replace-fail "root = '/usr/lib/storm/'" "root = '${storm-lang}/lib/storm/'"
          '';

          nativeCheckInputs = [
            neovim-unwrapped
            luajitPackages.busted
            luajitPackages.nlua
          ];

          doCheck = true;
          checkPhase = /* bash */ ''
            runHook preCheck
            export HOME=$(mktemp -d)
            cp -r ${testSrc}/spec ${testSrc}/.busted .
            # tests may write test data (:Storm reload package)
            chmod -R u+w spec
            busted --lua=nlua
            rm -rf spec .busted
            runHook postCheck
          '';
        };

      lint-tools =
        pkgs: with pkgs; [
          stylua
          selene
          lua-language-server
        ];

      lint-check =
        pkgs:
        pkgs.runCommand "storm-mode-nvim-lint"
          {
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./lua
                ./plugin
                ./spec
                ./.luarc.json
                ./selene.toml
                ./neovim.yml
                ./stylua.toml
              ];
            };
            nativeBuildInputs = lint-tools pkgs;
            VIMRUNTIME = "${pkgs.neovim-unwrapped}/share/nvim/runtime";
          }
          /* bash */ ''
            cd $src
            stylua --check lua plugin spec
            selene lua plugin spec
            export HOME=$(mktemp -d)
            lua-language-server --check . --checklevel=Warning --logpath=$HOME --check_out_path=$HOME/check.json
            touch $out
          '';

      # Storm builds on Linux only
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          stormLang = pkgs.callPackage ./nix/storm.nix { };
          stormModeNvim = pkgs.callPackage storm-mode-nvim { storm-lang = stormLang; };
        in
        {
          packages = {
            default = stormModeNvim;
            storm-mode-nvim = stormModeNvim;
            storm-lang = stormLang;
          };

          checks = {
            lint = lint-check pkgs;
            tests = stormModeNvim;
          };

          formatter = pkgs.writeShellApplication {
            name = "stylua-format";
            runtimeInputs = [ pkgs.stylua ];
            text = /* bash */ ''
              if [ "$#" -eq 0 ] || [ "$*" = "." ]; then set -- lua plugin spec; fi
              stylua "$@"
            '';
          };

          devShells.default = pkgs.mkShellNoCC {
            packages =
              with pkgs;
              [
                neovim
                luajitPackages.busted
                luajitPackages.nlua
                stormLang
              ]
              ++ lint-tools pkgs;

            shellHook = /* bash */ ''
              export STORM_MODE_NVIM_HOME=$(git rev-parse --show-toplevel) || exit
              export XDG_CONFIG_DIRS="$STORM_MODE_NVIM_HOME/.nvim_config:$XDG_CONFIG_DIRS"
              export STORM_COMPILER=${pkgs.lib.getExe stormLang}
              export STORM_ROOT=${stormLang}/lib/storm/
              # For lua-language-server's `vim` type definitions (.luarc.json)
              export VIMRUNTIME=${pkgs.neovim-unwrapped}/share/nvim/runtime
            '';
          };
        };

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (perSystem system));
    in
    {
      packages = forAllSystems (s: s.packages);
      checks = forAllSystems (s: s.checks);
      formatter = forAllSystems (s: s.formatter);
      devShells = forAllSystems (s: s.devShells);
    };
}
