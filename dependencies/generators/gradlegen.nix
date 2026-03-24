{ pkgs, stdenv, lib, wawonaAndroidProject ? null, wawonaSrc ? null, wawonaVersion ? "v1.0", iconAssets ? "AUTO" }:

let
  versionName = if wawonaVersion == null || wawonaVersion == "" then "v1.0"
    else if lib.hasPrefix "v" wawonaVersion then wawonaVersion
    else "v${wawonaVersion}";

  # Resolve icon assets:
  # 1. If explicitly null, use null (breaks recursion)
  # 2. If explicitly provided (not "AUTO"), use that derivation
  # 3. If "AUTO", try to resolve locally from wawonaSrc
  androidIconAssets = 
    if iconAssets == null then null
    else if iconAssets != "AUTO" then iconAssets
    else if wawonaSrc != null && builtins.pathExists ./android-icon-assets.nix then
      import ./android-icon-assets.nix { inherit pkgs lib wawonaSrc; }
    else
      null;

  buildGradle = pkgs.writeText "build.gradle.kts" ''
    buildscript {
        repositories {
            google()
            mavenCentral()
            maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        }
        dependencies {
            classpath("com.android.tools.build:gradle:8.10.0")
            classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.0.21")
        }
    }

    plugins {
        id("com.android.application") version "8.10.0"
        id("org.jetbrains.kotlin.android") version "2.0.21"
        id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    }

    android {
            namespace = "com.aspauldingcode.wawona"
            compileSdk = 36
            buildToolsVersion = "36.0.0"

            defaultConfig {
                applicationId = "com.aspauldingcode.wawona"
                minSdk = 36
                targetSdk = 36
                versionCode = 1
                versionName = "${versionName}"
            }

        buildTypes {
            release {
                isMinifyEnabled = false
                proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            }
            debug {
                isMinifyEnabled = false
                isJniDebuggable = true
                isDebuggable = true
            }
        }
        
        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        
        kotlinOptions {
            jvmTarget = "17"
        }
        
        buildFeatures {
            compose = true
        }
        
        sourceSets {
            getByName("main") {
                manifest.srcFile("AndroidManifest.xml")
                java.srcDirs("java")
                res.srcDirs("res")
                jniLibs.srcDirs("jniLibs")
            }
        }
    }

    dependencies {
        implementation("androidx.core:core-ktx:1.15.0")
        implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
        implementation("androidx.activity:activity-compose:1.9.3")
        implementation(platform("androidx.compose:compose-bom:2024.10.01"))
        implementation("androidx.compose.ui:ui:1.7.5")
        implementation("androidx.compose.ui:ui-graphics:1.7.5")
        implementation("androidx.compose.ui:ui-tooling-preview:1.7.5")
        implementation("androidx.compose.foundation:foundation:1.7.5")
        implementation("androidx.compose.material3:material3:1.3.1")
        implementation("androidx.compose.material3:material3-window-size-class:1.3.1")
        implementation("androidx.compose.material:material-icons-extended:1.7.5")
        implementation("androidx.compose.animation:animation:1.7.5")
        
        implementation("androidx.appcompat:appcompat:1.7.0")
        implementation("androidx.fragment:fragment-ktx:1.8.9")
    }
  '';

  settingsGradle = pkgs.writeText "settings.gradle.kts" ''
    pluginManagement {
        println("Settings: offline mode is ''${gradle.startParameter.isOffline}")
        gradle.startParameter.isOffline = false
        println("Settings: forced offline mode to ''${gradle.startParameter.isOffline}")

        resolutionStrategy {
            eachPlugin {
                if (requested.id.id == "com.android.application") {
                useModule("com.android.tools.build:gradle:8.10.0")
            }
            }
        }
        repositories {
            maven {
                url = uri("https://dl.google.com/dl/android/maven2/")
            }
            google()
            mavenCentral()
            gradlePluginPortal()
        }
    }
    dependencyResolutionManagement {
        repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
        repositories {
            google()
            mavenCentral()
        }
    }
    rootProject.name = "Wawona"
  '';

  # Script to generate Android Studio project in _GEN-android/ (gitignored).
  # When wawonaAndroidProject is available (pre-built Android project with jniLibs),
  # copies the full project. Otherwise falls back to gradle files + sources only.
  projectPath = if wawonaAndroidProject != null then toString wawonaAndroidProject else "";
  outDir = "_GEN-android";
  generateScript = pkgs.writeShellScriptBin "gradlegen" ''
    set -e
    OUT="${outDir}"

    # Clean previous run (handles read-only Nix store copies)
    if [ -d "$OUT" ]; then
      chmod -R u+w "$OUT" 2>/dev/null || true
      rm -rf "$OUT"
    fi
    mkdir -p "$OUT"

    if [ -n "${projectPath}" ] && [ -d "${projectPath}" ]; then
      echo "Copying full Android project (backend + native libs) to $OUT/..."
      cp -r ${projectPath}/* "$OUT/"
      chmod -R u+w "$OUT" 2>/dev/null || true
      echo ""
      echo "Project ready at $OUT/"
      echo "Open $OUT/ in Android Studio and select device/emulator."
    else
      cp ${buildGradle} "$OUT/build.gradle.kts"
      cp ${settingsGradle} "$OUT/settings.gradle.kts"
      chmod u+w "$OUT/build.gradle.kts" "$OUT/settings.gradle.kts"
      if [ -d "src/platform/android" ]; then
        mkdir -p "$OUT/java" "$OUT/res"
        cp -r src/platform/android/java/* "$OUT/java/" 2>/dev/null || true
        cp -r src/platform/android/res/* "$OUT/res/" 2>/dev/null || true
        cp src/platform/android/AndroidManifest.xml "$OUT/" 2>/dev/null || true
        chmod -R u+w "$OUT/res" 2>/dev/null || true
        ${if androidIconAssets != null then ''
          if [ -d "${androidIconAssets}/res" ]; then
            cp -r ${androidIconAssets}/res/* "$OUT/res/"
            chmod -R u+w "$OUT/res" 2>/dev/null || true
            echo "Merged Wawona launcher icon assets"
          fi
        '' else ""}
        echo "Generated gradle files + Android sources in $OUT/ (no jniLibs - run nix build .#wawona-android first for full project)"
      else
        echo "Generated build.gradle.kts and settings.gradle.kts in $OUT/"
      fi
    fi
  '';

in {
  inherit buildGradle settingsGradle generateScript;
}
