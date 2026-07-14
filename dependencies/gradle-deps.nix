{
  stdenv,
  lib,
  gradle,
  jdk17,
  androidSDK,
  wawonaSrc,
  pkgs,
  androidConfigNix,
}:

let
  androidConfig = import androidConfigNix {
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

      # Normalize daemon/jvmargs so --no-daemon stays in-process (no single-use
      # daemon TCP). Heap must match GRADLE_OPTS in gradleUpdateScript.
      if [ -f gradle.properties ]; then
        grep -v -E '^org\.gradle\.(jvmargs|daemon)=' gradle.properties > gradle.properties.nix
        mv gradle.properties.nix gradle.properties
        echo 'org.gradle.daemon=false' >> gradle.properties
        # Include -Xms64m so Wanted matches the gradle launcher client JVM.
        echo 'org.gradle.jvmargs=-Xms64m -Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8' >> gradle.properties
      fi
    '';

    gradleUpdateScript = ''
      runHook preBuild
      runHook preGradleUpdate
      # Always use Nix gradle: ./gradlew forceFetches the wrapper zip in sandbox.
      # Download all resolvable configuration artifacts without compiling app
      # sources (compileDebugKotlin needs anowaw bindings unavailable here).
      # Metadata-only `:dependencies` is not enough — mitm lockfile would drop AARs.
      # Match org.gradle.jvmargs + mitm trustStore so --no-daemon stays
      # in-process (no localhost single-use daemon in the Nix sandbox).
      GRADLE_OPTS="-Xms64m -Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8"
      if [ -n "''${MITM_CACHE_KEYSTORE-}" ] && [ -n "''${MITM_CACHE_KS_PWD-}" ]; then
        GRADLE_OPTS="''${GRADLE_OPTS} -Djavax.net.ssl.trustStore=''${MITM_CACHE_KEYSTORE} -Djavax.net.ssl.trustStorePassword=''${MITM_CACHE_KS_PWD}"
      fi
      export GRADLE_OPTS
      # Plugin markers (com.*.gradle.plugin poms) resolve during settings /
      # plugins {} configuration. resolveAllArtifacts only walks project
      # classpaths and never records AGP or Kotlin Compose plugin markers.
      gradle help \
        --no-daemon --max-workers=1 \
        -Dorg.gradle.daemon=false \
        -Dorg.gradle.parallel=false \
        -Dorg.gradle.workers.max=1 \
        --stacktrace
      cat > resolve-artifacts.init.gradle <<'EOF'
      gradle.projectsLoaded {
        rootProject.tasks.register("resolveAllArtifacts") {
          doLast {
            allprojects { project ->
              // Snapshot first — resolving can mutate the configurations container.
              def configs = project.configurations.findAll { it.canBeResolved }
              // Prefer app classpaths that pull AARs for assembleDebug.
              def preferred = configs.findAll { cfg ->
                def n = cfg.name
                n.contains("CompileClasspath") || n.contains("RuntimeClasspath") ||
                  n.contains("AnnotationProcessor") || n.startsWith("kotlin") ||
                  n.contains("lint") || n.contains("coreLibraryDesugaring")
              }
              (preferred ?: configs).each { config ->
                try {
                  def files = config.files
                  println "Resolved artifacts for ''${config.name}: ''${files.size()}"
                } catch (Throwable e) {
                  println "Skip ''${config.name}: ''${e.message}"
                }
              }
            }
          }
        }
      }
      EOF
      gradle resolveAllArtifacts -I resolve-artifacts.init.gradle \
        --no-daemon --max-workers=1 \
        -Dorg.gradle.daemon=false \
        -Dorg.gradle.parallel=false \
        -Dorg.gradle.workers.max=1 \
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
