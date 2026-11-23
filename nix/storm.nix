{
  lib,
  stdenv,
  fetchgit,
  makeFontsConf,
  mymake,
  pkg-config,
  gtk3,
  libX11,
  libGL,
  libpng,
  libjpeg,
  openal,
  mpg123,
  libvorbis,
  flac,
  openssl,
  mariadb-connector-c,
  libpq,
  libbacktrace,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "storm-lang";
  version = "0.8.2";

  src = fetchgit {
    url = "git://storm-lang.org/storm.git";
    rev = "adf7e4eb9a0bd71ce615482590f3cfaf3ccc5704";
    fetchSubmodules = true;
    hash = "sha256-W147QUNN311KtwKbsxBc2qLgGKgn9S0K7O9x6H5EAQY=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    mymake
    pkg-config
  ];

  buildInputs = [
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
    # sql: MariaDB headers (libpq needs none, see postPatch)
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
    # The SQL library dlopens the database client libraries. Absolute paths: an
    # rpath added by patchelf moves .dynstr, and Storm's own ELF check on its
    # libraries (Compiler/SharedOS.cpp) then rejects SQL.so
    substituteInPlace SQL/MariaDB/Driver.cpp --replace-fail '"libmariadb.so.3",' \
      '"${mariadb-connector-c}/lib/mariadb/libmariadb.so.3",'
    substituteInPlace SQL/PostgreSQL/Driver.cpp --replace-fail '"libpq.so.5",' \
      '"${lib.getLib libpq}/lib/libpq.so.5",'
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
    export FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ ]; }}
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
    license = with lib.licenses; [
      bsd2
      lgpl21 # progvis
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "storm";
  };
})
