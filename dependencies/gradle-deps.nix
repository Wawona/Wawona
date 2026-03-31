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

  # Allow network access for fixed-output derivation to fetch Gradle dependencies
  __noChroot = true;
  outputHashAlgo = "sha256";
  outputHashMode = "recursive";
  outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

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
    unset GRADLE_OPTS

    gradle --no-daemon --refresh-dependencies dependencies --configuration implementation --info --stacktrace
    gradle --no-daemon --refresh-dependencies dependencies --configuration debugImplementation --info --stacktrace
    gradle --no-daemon --refresh-dependencies dependencies --configuration androidTestImplementation --info --stacktrace

    # Also run assembleDebug to get build dependencies (plugins etc)
    gradle --no-daemon assembleDebug --dry-run --info --stacktrace || true
  '';

  installPhase = ''
    # Create a temporary directory to store our deterministic artifacts
    TEMP_STORE=$(mktemp -d)

    # Preserve ONLY dependency artifacts (jars, poms, modules)
    # These reside in caches/modules-2/files-2.1 and are inherently deterministic
    if [ -d "$out/caches/modules-2/files-2.1" ]; then
      echo "Preserving deterministic dependency artifacts..."
      mv "$out/caches/modules-2/files-2.1" "$TEMP_STORE/"
    fi

    # Wipe out EVERYTHING else in the output directory (volatile metadata, binary logs, etc.)
    echo "Purging non-deterministic caches and binary blobs..."
    rm -rf "$out"/*

    # Restore the whitelisted artifacts to a predictable structure
    echo "Restoring whitelisted artifacts to output..."
    mkdir -p "$out/caches/modules-2"
    if [ -d "$TEMP_STORE/files-2.1" ]; then
      mv "$TEMP_STORE/files-2.1" "$out/caches/modules-2/"
    fi

    # Clean up
    rm -rf "$TEMP_STORE"

    # Final determinism audit: sanitize any surviving absolute paths in text files (poms, xmls)
    echo "Performing final determinism audit and path sanitization..."
    grep -r -l "/nix/build" "$out" | while read -r file; do
       if file "$file" | grep -q "text"; then
          echo "Sanitizing build path in $file"
          sed -i "s|/nix/build|/no-build|g" "$file"
       fi
    done || true
  '';
}
}
