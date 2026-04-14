{
  lib,
  stdenv,
  fetchFromGitHub,
  swift,
  swiftpm ? null,
  git,
  makeWrapper,
  gradle,
  jdk17 ? null,
  openjdk ? null,
  cacert,
  curl,
  libxml2,
  libarchive ? null,
  zlib-ng-compat ? null,
}:

let
  version = "1.8.6";
  skipSubmodule = fetchFromGitHub {
    owner = "skiptools";
    repo = "skip";
    rev = version;
    sha256 = "sha256-tCgoiYW6l6aUSapXYZDoLrDnbruD3WHb8a9Yk46MacU=";
  };
  javaRuntime = if jdk17 != null then jdk17 else openjdk;
  runtimePath =
    if stdenv.isDarwin then
      "/usr/bin:${lib.makeBinPath [ gradle git javaRuntime ]}"
    else
      lib.makeBinPath ([ swift gradle git javaRuntime ] ++ lib.optionals (swiftpm != null) [ swiftpm ]);
in
stdenv.mkDerivation rec {
  pname = "skip";
  inherit version;

  src = fetchFromGitHub {
    owner = "skiptools";
    repo = "skipstone";
    rev = version;
    sha256 = "sha256-bq3Uk30DQ2ErtF/4PYSTAjIuIQ2gm+kG/pyKKr5W/sQ=";
  };

  nativeBuildInputs = [ swift cacert makeWrapper ] ++ lib.optionals (swiftpm != null) [ swiftpm ];

  buildInputs =
    [
      gradle
      javaRuntime
      curl
      libxml2
    ]
    ++ lib.optionals stdenv.isLinux [
      libarchive
      zlib-ng-compat
    ];

  postPatch = ''
    rm -rf skip
    cp -R ${skipSubmodule} skip
    chmod -R u+w skip
  '';

  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  NIX_SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  buildPhase = ''
    runHook preBuild
    swift build \
      ${lib.optionalString stdenv.isDarwin "--disable-sandbox"} \
      ${lib.optionalString stdenv.isLinux "--static-swift-stdlib -Xswiftc -use-ld=ld"} \
      --configuration release \
      --product SkipRunner
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 .build/release/SkipRunner "$out/bin/skip"
    wrapProgram "$out/bin/skip" \
      --prefix PATH : "${runtimePath}"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Tool for building Swift apps for Android";
    homepage = "https://skip.dev";
    license = licenses.agpl3Only;
    mainProgram = "skip";
    platforms = platforms.unix;
  };
}
