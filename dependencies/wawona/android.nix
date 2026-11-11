# The APK (or AAB): the committed Gradle project at the repository root, run
# offline with .deps linked as `nix run .#deps -- android` links it.
{
  lib,
  pkgs,
  wawonaSrc,
  depsAndroid,
  wawonaVersion,
  androidSDK,
  androidUtils,
  androidToolchain,
  androidConfigNix,
  terminalSrc,
  toolbarKeysSrc,
  # Linux: JBR 21. Darwin Nix sandbox: OpenJDK (nixpkgs JBR is Linux-only).
  jdk17,
  gradle,
  releaseArtifact ? "debug",
}:
let
  androidConfig = import androidConfigNix {
    inherit lib androidSDK;
    system = pkgs.stdenv.buildPlatform.system;
  };
  gradleSupport = pkgs.callPackage ../gradle-deps.nix { inherit wawonaSrc androidSDK androidConfigNix gradle jdk17; };
  inherit (gradleSupport) mitmCache;
  isAab = releaseArtifact == "release-aab";
  isRelease = releaseArtifact != "debug";
  gradleTask = if isAab then ":Wawona:bundleRelease" else if isRelease then ":Wawona:assembleRelease" else ":Wawona:assembleDebug";

  # AGP's plugin graph asks for kotlin-stdlib/reflect 2.4.10; the mitm cache stops at 2.2.10.
  kotlin2410 = pkgs.linkFarm "kotlin-2.4.10-maven" (map (f: {
    name = "org/jetbrains/kotlin/${f.path}";
    path = pkgs.fetchurl { url = "https://repo1.maven.org/maven2/org/jetbrains/kotlin/${f.path}"; inherit (f) hash; };
  }) [
    { path = "kotlin-stdlib/2.4.10/kotlin-stdlib-2.4.10.pom"; hash = "sha256-n4HyXpa5GRUzkt7VO9MyFudmJJCc/QgKPtsnjUT8NPA="; }
    { path = "kotlin-stdlib/2.4.10/kotlin-stdlib-2.4.10.jar"; hash = "sha256-TsApO8N1FCOyA/HYSTJRxXxC5z62N3prhWDQl0/wpt8="; }
    { path = "kotlin-stdlib/2.4.10/kotlin-stdlib-2.4.10.module"; hash = "sha256-HASpjxIAyHBdAV3wiXchFYnuy8h88cTG0oqSaC/oRG4="; }
    { path = "kotlin-reflect/2.4.10/kotlin-reflect-2.4.10.pom"; hash = "sha256-QljwIS9L1y4wR/farOOODeLr/z9+kj6DZDH9j1sZGJ0="; }
    { path = "kotlin-reflect/2.4.10/kotlin-reflect-2.4.10.jar"; hash = "sha256-JaGu90VNRlSOyq9RAhsOUuOBQaYu11rxJNoQm3MkxOU="; }
  ]);
  # HTTPS through the mitm proxy fails in the Darwin sandbox, so Gradle reads
  # the cache as file:// repositories instead (settings.gradle.kts).
  maven = lib.concatMapStringsSep " " (d: "file://${d}") [
    kotlin2410
    "${mitmCache}/https/dl.google.com/dl/android/maven2"
    "${mitmCache}/https/plugins.gradle.org/m2"
    "${mitmCache}/https/repo.maven.apache.org/maven2"
  ];

  # Release signing is read at impure eval: daemon builders do not see the
  # client's environment. Only `--impure` release builds set these.
  env = builtins.getEnv;
  buildNumber = if env "WAWONA_BUILD_NUMBER" == "" then "1" else env "WAWONA_BUILD_NUMBER";
  versionName = if env "WAWONA_VERSION" == "" then wawonaVersion else lib.removePrefix "v" (env "WAWONA_VERSION");

  runnerScript = import ./android-runner.nix {
    inherit pkgs;
    nixSdkPath = lib.makeBinPath ([ androidSDK.platformTools androidSDK.cmdlineTools androidSDK.androidsdk pkgs.util-linux jdk17 pkgs.lldb ]
      ++ lib.optionals androidConfig.emulatorSupported [ androidSDK.emulator ]);
    nixSdkRoot = androidConfig.sdkRoot;
    provisionScript = "${androidUtils.provisionAndroidScript}/bin/provision-android";
    androidndkRoot = androidToolchain.androidndkRoot;
    systemImageId = androidConfig.systemImageId;
  };
in
pkgs.stdenv.mkDerivation {
  name = "wawona-android";
  version = wawonaVersion;
  src = wawonaSrc;
  dontFixup = true;
  dontUseGradleBuild = true;
  dontUseGradleCheck = true;
  __darwinAllowLocalNetworking = true;
  inherit mitmCache;
  inherit (gradleSupport) gradleFlags;
  nativeBuildInputs = [ jdk17 gradle ];

  buildPhase = ''
    runHook preBuild
    ${gradleSupport.prepareEnvironment}
    export ANDROID_NDK_ROOT=${androidToolchain.androidndkRoot} ANDROID_NDK_HOME=${androidToolchain.androidndkRoot}
    export WAWONA_VERSION=${versionName} WAWONA_BUILD_NUMBER=${buildNumber}
    mkdir -p .deps
    ln -s ${depsAndroid} .deps/android
    ln -s ${terminalSrc} .deps/terminal
    ln -s ${toolbarKeysSrc} .deps/toolbar-keys
    ${lib.optionalString isRelease ''
      export ANDROID_KEYSTORE_PASSWORD="${env "ANDROID_KEYSTORE_PASSWORD"}"
      export ANDROID_KEY_ALIAS="${env "ANDROID_KEY_ALIAS"}"
      export ANDROID_KEY_PASSWORD="${env "ANDROID_KEY_PASSWORD"}"
      # Host RUNNER_TEMP paths are not readable in the sandbox; prefer the base64 form.
      if [ -n "${env "ANDROID_KEYSTORE_BASE64"}" ]; then
        printf '%s' "${env "ANDROID_KEYSTORE_BASE64"}" | base64 -d > "$TMPDIR/upload.jks"
        export ANDROID_KEYSTORE_PATH="$TMPDIR/upload.jks"
      else
        export ANDROID_KEYSTORE_PATH="${env "ANDROID_KEYSTORE_PATH"}"
      fi
      : "''${ANDROID_KEYSTORE_PATH:?Set ANDROID_KEYSTORE_BASE64}" "''${ANDROID_KEYSTORE_PASSWORD:?}" "''${ANDROID_KEY_ALIAS:?}" "''${ANDROID_KEY_PASSWORD:?}"
    ''}
    # Matches org.gradle.jvmargs so --no-daemon stays in-process (no localhost daemon in the sandbox).
    export GRADLE_OPTS="-Xms64m -Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8"
    # The Nix gradle, not ./gradlew: the wrapper downloads its distribution.
    gradle ${gradleTask} --offline --no-build-cache --no-watch-fs --no-daemon --stacktrace "-Pwawona.maven=${maven}"
    runHook postBuild
  '';

  installPhase = if isAab then ''
    mkdir -p $out/bin
    cp android/app/build/outputs/bundle/release/*.aab $out/bin/Wawona.aab
  '' else ''
    mkdir -p $out/bin
    cp android/app/build/outputs/apk/*/*.apk $out/bin/Wawona.apk
    cp ${runnerScript} $out/bin/wawona-android-run
    chmod +x $out/bin/wawona-android-run
  '';
}
