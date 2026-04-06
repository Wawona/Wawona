{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
in

{
  buildForMacOS =
    name: entry:
    if name == "libwayland" then
      pkgs.callPackage ../libs/libwayland/macos.nix { inherit common buildModule; }
    else if name == "expat" then
      pkgs.callPackage ../libs/expat/macos.nix { inherit common; }
    else if name == "libffi" then
      pkgs.callPackage ../libs/libffi/macos.nix { inherit common; }
    else if name == "libxml2" then
      pkgs.callPackage ../libs/libxml2/macos.nix { }
    else if name == "waypipe" then
      pkgs.callPackage ../libs/waypipe/macos.nix { inherit common buildModule; }
    else if name == "zstd" then
      pkgs.callPackage ../libs/zstd/macos.nix { inherit common buildModule; }
    else if name == "lz4" then
      pkgs.callPackage ../libs/lz4/macos.nix { inherit common buildModule; }
    else if name == "pixman" then
      pkgs.pixman
    else if name == "xkbcommon" then
      pkgs.libxkbcommon
    else if name == "ffmpeg" then
      pkgs.callPackage ../libs/ffmpeg/macos.nix { inherit common buildModule; }
    else
      let
        src = fetchSource entry;
        buildSystem = getBuildSystem entry;
        buildFlags = entry.buildFlags.macos or [ ];
        patches = lib.filter (p: p != null && builtins.pathExists (toString p)) (
          entry.patches.macos or [ ]
        );
        getDeps =
          depNames:
          map (
            depName:
            if depName == "expat" then
              pkgs.expat
            else if depName == "libffi" then
              pkgs.libffi
            else if depName == "libxml2" then
              pkgs.libxml2
            else if depName == "libclc" then
              pkgs.libclc
            else if depName == "zlib" then
              pkgs.zlib
            else if depName == "zstd" then
              pkgs.zstd
            else if depName == "llvm" then
              pkgs.llvmPackages.llvm
            else
              throw "Unknown dependency: ${depName}"
          ) depNames;
        depInputs = getDeps (entry.dependencies.macos or [ ]);
      in
      if buildSystem == "cmake" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-macos";
          inherit src patches;
          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
          ];
          buildInputs = depInputs;
          cmakeFlags = buildFlags;
        }
      else if buildSystem == "meson" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-macos";
          inherit src patches;
          nativeBuildInputs = with pkgs; [
            meson
            ninja
            pkg-config
            (python3.withPackages (
              ps: with ps; [
                setuptools
                pip
                packaging
                mako
                pyyaml
              ]
            ))
            bison
            flex
          ];
          buildInputs = depInputs;
          configurePhase = ''
            runHook preConfigure
            meson setup build \
              --prefix=$out \
              --libdir=$out/lib \
              ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
            runHook postConfigure
          '';
          buildPhase = ''
            runHook preBuild
            meson compile -C build
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            meson install -C build
            runHook postInstall
          '';
        }
      else if buildSystem == "cargo" || buildSystem == "rust" then
        pkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          cargoHash = if entry ? cargoHash && entry.cargoHash != null then entry.cargoHash else lib.fakeHash;
          cargoSha256 = entry.cargoSha256 or null;
          cargoLock = entry.cargoLock or null;
          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = depInputs;
        }
      else
        pkgs.stdenv.mkDerivation {
          name = "${name}-macos";
          inherit src patches;
          nativeBuildInputs = with pkgs; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          buildInputs = depInputs;
          configureFlags = buildFlags;
        };
}
