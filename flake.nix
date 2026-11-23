{
  description = "storm-mode.nvim Development Environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
    }:
    let
      build-storm-lang =
        pkgs:
        pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "storm-lang";
          version = "0.8.2";

          src = pkgs.fetchgit {
            url = "git://storm-lang.org/storm.git";
            rev = "adf7e4eb9a0bd71ce615482590f3cfaf3ccc5704";
            fetchSubmodules = true;
            hash = "sha256-W147QUNN311KtwKbsxBc2qLgGKgn9S0K7O9x6H5EAQY=";
          };

          nativeBuildInputs = with pkgs; [
            mymake
            pkg-config
          ];

          buildInputs = with pkgs; [
            # ui
            gtk3
            libX11
            libGL
            # graphics
            libpng
            libjpeg
            # sound
            openal
            mpg123
            libvorbis
            flac
            # crypto
            openssl
            # sql
            mariadb-connector-c
            # Stack traces
            libbacktrace
          ];

          mmFlags = [
            "release"
            "dist"
            "nostatic"
            "noskia"
            "mps"
            "reproducible"
          ];

          postPatch = /* bash */ ''
            substituteInPlace Main/.mymake --replace-fail /usr/lib/storm $out/lib/storm
            printf 'core.info\n%s\n' ${finalAttrs.version} > Compiler/COMPILER.version
          '';

          buildPhase = /* bash */ ''
            runHook preBuild
            mm --global-config mymake.conf -j $NIX_BUILD_CORES --config
            mm --global-config mymake.conf -j $NIX_BUILD_CORES $mmFlags Main
            runHook postBuild
          '';

          # Storm's own test suite
          doCheck = true;
          preCheck = /* bash */ ''
            substituteInPlace Test/Core/NetTest.cpp --replace-fail \
              'CHECK_GTE(lookupAddress(new (e) Str(S("storm-lang.org")))->count(), Nat(1));' ""
            substituteInPlace Test/Storm/Shared.cpp \
              --replace-fail 'BEGIN_TEST(Shared, Storm)' 'BEGIN_TESTX(Shared, Storm)'
            export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ ]; }}
            export XDG_CACHE_HOME=$TMPDIR/cache
          '';
          checkPhase = /* bash */ ''
            runHook preCheck
            mm --global-config mymake.conf -j $NIX_BUILD_CORES $mmFlags Test
            release/Test_mps --all
            runHook postCheck
          '';

          installPhase = /* bash */ ''
            runHook preInstall
            install -Dm755 release/Storm_mps $out/bin/storm
            mkdir -p $out/lib
            cp -r root $out/lib/storm
            rm -rf $out/lib/storm/server-tests
            runHook postInstall
          '';

          meta = {
            description = "Storm extensible programming language platform";
            homepage = "https://storm-lang.org/";
            license = with pkgs.lib.licenses; [
              bsd2
              lgpl21 # progvis
            ];
            platforms = [
              "x86_64-linux"
              "aarch64-linux"
            ];
            mainProgram = "storm";
          };
        });

      build-storm-mode-nvim =
        pkgs: stormLang:
        let
          fs = pkgs.lib.fileset;
          # buildVimPlugin generates doc/tags (vimGenDocHook runs :helptags on $out/doc)
          pluginSrc = fs.toSource {
            root = ./.;
            fileset = fs.unions [
              ./lua
              (fs.difference ./doc (fs.maybeMissing ./doc/tags))
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
        pkgs.vimUtils.buildVimPlugin {
          pname = "storm-mode.nvim";
          version = "2.0.0"; # x-release-please-version
          src = pluginSrc;

          nativeCheckInputs = [
            pkgs.neovim-unwrapped
            pkgs.luajitPackages.busted
            pkgs.luajitPackages.nlua
            stormLang
          ];

          doCheck = true;
          checkPhase = /* bash */ ''
            runHook preCheck
            export HOME=$(mktemp -d)
            # spec/helper.lua configures storm-mode from these
            export STORM_COMPILER=${pkgs.lib.getExe stormLang}
            export STORM_ROOT=${stormLang}/lib/storm/
            cp -r ${testSrc}/spec ${testSrc}/.busted .
            chmod -R u+w spec # tests may write test data (:Storm reload package)
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
            src = ./.;
            nativeBuildInputs = lint-tools pkgs;
            VIMRUNTIME = "${pkgs.neovim-unwrapped}/share/nvim/runtime";
          }
          /* bash */ ''
            cd $src
            stylua --check lua spec
            selene lua spec
            export HOME=$(mktemp -d)
            lua-language-server --check . --checklevel=Warning --logpath=$HOME --check_out_path=$HOME/check.json
            touch $out
          '';

      outputs = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          stormLang = build-storm-lang pkgs;
          stormModeNvim = build-storm-mode-nvim pkgs stormLang;
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

          # `nix fmt`: format the Lua sources
          formatter = pkgs.writeShellApplication {
            name = "stylua-format";
            runtimeInputs = [ pkgs.stylua ];
            text = /* bash */ ''
              if [ "$#" -eq 0 ] || [ "$*" = "." ]; then set -- lua spec; fi
              stylua "$@"
            '';
          };

          devShells.default = pkgs.mkShellNoCC {
            buildInputs =
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
        }
      );
    in
    outputs;
}
