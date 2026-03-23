{
  stdenv,
  lib,
  gradle,
  jdk17,
  git,
  androidSDK,
  wawonaSrc,
  pkgs,
  gradlegen,
}:

stdenv.mkDerivation {
  pname = "wawona-android-gradle-deps";
  version = "1.0.0";

  src = wawonaSrc;

  nativeBuildInputs = [
    gradle
    jdk17
    git
    pkgs.cacert
    pkgs.curl
    pkgs.openssl
  ];

  outputHashAlgo = "sha256";
  outputHashMode = "recursive";
  outputHash = "sha256-JiPTNC5db4LXBa0sUcg6VeO3DiEU0a3reqzIXlUjow0=";

  buildPhase = ''
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export GRADLE_OPTS="-Djava.net.preferIPv4Stack=true -Djava.net.preferIPv6Addresses=false"
    export GRADLE_USER_HOME=$out
    export JAVA_HOME="${jdk17}"
    export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"

    # Create a writable Android User Home for license acceptance and other state
    export ANDROID_USER_HOME=$(mktemp -d)

    # Accept licenses
    mkdir -p $ANDROID_USER_HOME/licenses
    echo "24333f8a63b6825ea9c5514f83c2829b004d1fee" > $ANDROID_USER_HOME/licenses/android-sdk-license

    # Use JDK's cacerts directly
    REAL_JAVA_HOME=$(find ${jdk17} -name cacerts | head -n 1 | sed 's|/lib/security/cacerts||')
    echo "Using trustStore at: $REAL_JAVA_HOME/lib/security/cacerts"
    ls -l "$REAL_JAVA_HOME/lib/security/cacerts"
    # export GRADLE_OPTS="$GRADLE_OPTS -Djavax.net.ssl.trustStore=$REAL_JAVA_HOME/lib/security/cacerts -Djavax.net.ssl.trustStorePassword=changeit"

    echo "Checking network connectivity..."
    curl -f -I https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/8.10.0/gradle-8.10.0.pom || echo "AGP 8.10.0 POM check failed"

    # Generate Gradle files
    mkdir -p project-root
    cd project-root
    cp ${gradlegen.buildGradle} build.gradle.kts
    cp ${gradlegen.settingsGradle} settings.gradle.kts
    chmod u+w build.gradle.kts settings.gradle.kts

    # Create a dummy AndroidManifest.xml and source structure since Gradle might need it
    mkdir -p java
    mkdir -p res
    cat > AndroidManifest.xml <<EOF
    <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.aspauldingcode.wawona">
        <application />
    </manifest>
    EOF

    # We use a custom init script to ensure we don't fail on missing signing config
    gradle --version

    # Try with explicit --refresh-dependencies and ensuring online
    # Also unset GRADLE_OPTS just in case
    unset GRADLE_OPTS

    gradle --no-daemon --refresh-dependencies dependencies --configuration implementation --info --stacktrace
    gradle --no-daemon --refresh-dependencies dependencies --configuration debugImplementation --info --stacktrace
    gradle --no-daemon --refresh-dependencies dependencies --configuration androidTestImplementation --info --stacktrace

    # Also run assembleDebug to get build dependencies (plugins etc)
    # This might fail due to read-only filesystem or other issues, so we allow failure
    # but we hope it downloads what it needs first.
    gradle --no-daemon assembleDebug --dry-run --info --stacktrace || true
  '';

  installPhase = ''
    # Clean up non-deterministic files
    find $out -name "*.lock" -delete
    find $out -name "gc.properties" -delete

    # Remove build-specific caches that might contain absolute paths or timestamps
    rm -rf $out/caches/*/plugin-resolution/
    rm -rf $out/caches/*/scripts/
    rm -rf $out/caches/*/scripts-remapped/
    rm -rf $out/caches/*/fileHashes/
    rm -rf $out/caches/*/workerMain/
    rm -rf $out/caches/*/file-changes/
    rm -rf $out/caches/*/journal/
    rm -rf $out/caches/transforms-*/
    rm -rf $out/caches/build-cache-1/
    rm -rf $out/daemon
    rm -rf $out/wrapper

    # Remove compiled scripts which capture the init script path
    rm -rf $out/caches/jars-*

    # Remove non-deterministic metadata binaries and volatile caches
    find $out -name "artifact-at-repository.bin" -delete
    find $out -name "module-versions.xml" -delete
    find $out -name "resource-at-url.bin" -delete
    find $out -name "module-artifacts.bin" -delete
    find $out -name "module-metadata.bin" -delete
    rm -rf $out/caches/*/generated-gradle-jars/
    rm -rf $out/caches/modules-2/metadata-*/

    # Remove files containing Nix store paths or build-time paths
    # We use a loop to avoid xargs issues and handle empty results
    # (grep returns 1 if no matches, so we use || true)
    grep -r -l "/nix/store" $out | while read -r file; do
      echo "Removing $file containing store path"
      rm -f "$file"
    done || true

    if [ -n "''${NIX_BUILD_TOP:-}" ]; then
      grep -r -l "$NIX_BUILD_TOP" $out | while read -r file; do
        echo "Removing $file containing build top path"
        rm -f "$file"
      done || true
    fi
  '';
}
