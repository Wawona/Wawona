{
  stdenv,
  lib,
  gradle,
  jdk17,
  androidSDK,
  wawonaSrc,
  pkgs,
}:

let
  androidConfig = import ./android/sdk-config.nix {
    inherit lib androidSDK;
    system = stdenv.buildPlatform.system;
  };
  androidIconAssets =
    if builtins.pathExists ./generators/android-icon-assets.nix then
      pkgs.callPackage ./generators/android-icon-assets.nix {
        inherit wawonaSrc;
      }
    else
      null;
  sdkRoot = androidConfig.sdkRoot;
  commonGradleFlags = [
    "-Dorg.gradle.java.home=${jdk17}"
    "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/${androidConfig.buildToolsVersion}/aapt2"
    "-Pandroid.suppressUnsupportedCompileSdk=${toString androidConfig.compileSdk}"
  ];
  prepareEnvironmentScript = ''
    export JAVA_HOME="${jdk17}"
    export ANDROID_SDK_ROOT="${sdkRoot}"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export ANDROID_USER_HOME="$(pwd)/.android-home"
    mkdir -p "$ANDROID_USER_HOME"
  '';
  prepareProjectScript = ''
    chmod -R u+w .
    cp -r android/* .
    chmod -R u+w .

    if [ -n "${if androidIconAssets != null then toString androidIconAssets else ""}" ] && [ -d "${if androidIconAssets != null then toString androidIconAssets else ""}/res" ]; then
      mkdir -p app/src/main/res
      cp -r ${if androidIconAssets != null then "${androidIconAssets}/res/." else "/dev/null"} app/src/main/res/
      chmod -R u+w app/src/main/res
      echo "Merged Wawona launcher icon assets"
    fi
  '';
  depsPackage = stdenv.mkDerivation {
    pname = "wawona-android-gradle-deps";
    version = "1.0.0";
    src = wawonaSrc;

    nativeBuildInputs = [
      gradle
      jdk17
    ];

    dontUseGradleBuild = true;
    dontUseGradleCheck = true;
    __darwinAllowLocalNetworking = true;
    gradleFlags = commonGradleFlags;

    preBuild = ''
      ${prepareProjectScript}
      ${prepareEnvironmentScript}
      ndk_root="$ANDROID_SDK_ROOT/ndk/${androidConfig.ndkVersion}"
      export ANDROID_NDK_ROOT="$ndk_root"
      export ANDROID_NDK_HOME="$ndk_root"

      # Force daemonless behavior in sandboxed CI prefetch runs.
      if [ -f gradle.properties ]; then
        grep -v -E '^org\.gradle\.(jvmargs|daemon)=' gradle.properties > gradle.properties.nix
        mv gradle.properties.nix gradle.properties
      fi
    '';

    gradleUpdateScript = ''
      runHook preBuild
      runHook preGradleUpdate
      gradle :app:dependencies :app:compileDebugKotlin :app:mergeDebugResources :app:desugarDebugFileDependencies \
        --no-daemon --max-workers=1 \
        -Dorg.gradle.daemon=false \
        -Dorg.gradle.parallel=false \
        -Dorg.gradle.workers.max=1 \
        -Dkotlin.daemon.enabled=false \
        -Dkotlin.compiler.execution.strategy=in-process \
        -Dkotlin.incremental=false \
        --stacktrace
      runHook postGradleUpdate
    '';

    buildPhase = ''
      mkdir -p "$out"
      echo "gradle deps helper" > "$out/marker"
    '';
  };
in
{
  depsFile = ./gradle-deps.json;

  mitmCache = gradle.fetchDeps {
    pkg = depsPackage;
    data = ./gradle-deps.json;
    silent = false;
    useBwrap = false;
  };

  gradleFlags = commonGradleFlags;

  prepareEnvironment = prepareEnvironmentScript;
  prepareProject = prepareProjectScript;
}
