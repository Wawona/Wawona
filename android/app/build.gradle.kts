import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val skipArtifactsDir = File(
    System.getenv("SKIP_ARTIFACTS_DIR") ?: rootProject.file("android/Skip").path
)
val skipRoots = listOf(skipArtifactsDir)

// Match Skip skipstone (`androidx.compose:compose-bom:2026.03.00` → Compose 1.10.5, material3-android 1.4.0).
val composeBom = "2026.03.00"
// Legacy coords from material-ripple still resolve non-`-android` artifacts; pin to same Compose line as BOM.
val composeAndroidSubstitutionVersion = "1.10.5"
// Skip skipstone `androidx-nav3` (TabView / NavBackStack); not embedded in SkipUI AAR.
val androidxNav3 = "1.0.1"
// Must match root `android/build.gradle.kts` Kotlin plugin; kotlin-reflect + stdlib SpillingKt.
val kotlinToolchain = "2.1.21"
// Skip skipstone `androidx-material3-adaptive`; EnvironmentValues / sheets need WindowAdaptiveInfoKt.
val material3Adaptive = "1.2.0"

fun File.hasSkipArtifacts(): Boolean {
    val sourceCandidates = listOf(
        resolve("Sources"),
        resolve("src/main/java"),
        resolve("src/main/kotlin")
    )
    val hasSources = sourceCandidates.any { dir ->
        dir.exists() && dir.walkTopDown().any { it.isFile && (it.extension == "kt" || it.extension == "java") }
    }
    val hasAars = exists() && walkTopDown().any { it.isFile && it.extension == "aar" }
    return hasSources || hasAars
}

val ensureSkipArtifacts = tasks.register("ensureSkipArtifacts") {
    doLast {
        val skipExportStrategy = System.getenv("SKIP_EXPORT_STRATEGY") ?: "skip-live-export"
        if (skipExportStrategy != "nix-prebuilt") return@doLast
        if (skipRoots.any { it.hasSkipArtifacts() }) return@doLast

        skipArtifactsDir.mkdirs()
        throw GradleException(
            "Expected prebuilt Skip artifacts at ${skipArtifactsDir.path} but none were found. " +
                "Active strategy: $skipExportStrategy. " +
                "Nix must run skip export and provide deterministic artifacts before Gradle."
        )
    }
}

val skipSourceDirs = skipRoots.flatMap { root ->
    listOf(
        root.resolve("Sources"),
        root.resolve("src/main/java"),
        root.resolve("src/main/kotlin")
    )
}

val skipResDirs = skipRoots.map { it.resolve("Resources/Android/res") }
val existingSkipSourceDirs = skipSourceDirs.filter { it.exists() }
val existingSkipResDirs = skipResDirs.filter { it.exists() }
// Skip-transpiled contracts compiled into the app so we are not stuck on a stale
// WawonaUIContracts-debug.aar when `skip export` fails (e.g. missing Xcode projects).
// These paths must be git-tracked: Nix flakes omit untracked files, and excluding the
// AAR without the overlay removes MachineEditorValidation from the APK entirely.
val wawonaUIContractsKotlinDir = rootProject.file("wawona-uicontracts-kotlin")
val wawonaUIContractsKotlinOverlayOk = wawonaUIContractsKotlinDir
    .resolve("wawona/uicontracts/MachineEditorContracts.kt")
    .isFile
val wawonaAppTarget = (System.getenv("WAWONA_APP_TARGET") ?: "android").lowercase()

android {
    namespace = "com.aspauldingcode.wawona"
    compileSdk = 36
    buildToolsVersion = "36.1.0"
    ndkVersion = "29.0.14206865"

    defaultConfig {
        applicationId = "com.aspauldingcode.wawona"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.2.3"
        buildConfigField("String", "WAWONA_APP_TARGET", "\"$wawonaAppTarget\"")

        ndk {
            abiFilters += "arm64-v8a"
        }

        externalNativeBuild {
            cmake {
                cppFlags("-fPIC")
                
                // When building under Nix, DEP_INCLUDES is populated in the environment.
                // We pass it to CMake as a property so it can include external Nix paths.
                val nixIncludes = System.getenv("DEP_INCLUDES") ?: ""
                if (nixIncludes.isNotEmpty()) {
                    arguments("-DNIX_DEP_INCLUDES=${nixIncludes}")
                }
                
                // Linker paths for Nix external dependencies 
                val nixLibs = System.getenv("DEP_LIBS") ?: ""
                if (nixLibs.isNotEmpty()) {
                    arguments("-DNIX_DEP_LIBS=${nixLibs}")
                }
                
                // Rust Backend Object
                val rustLib = System.getenv("RUST_BACKEND_LIB") ?: ""
                if (rustLib.isNotEmpty()) {
                    arguments("-DRUST_BACKEND_LIB=${rustLib}")
                }
            }
        }
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

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
        // Allow consuming prebuilt Skip AARs with newer Kotlin metadata.
        freeCompilerArgs += "-Xskip-metadata-version-check"
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    sourceSets {
        getByName("main") {
            val javaDirs = mutableListOf("src/main/java", "src/main/kotlin")
            javaDirs.addAll(existingSkipSourceDirs.map { it.path })
            if (wawonaUIContractsKotlinOverlayOk) {
                javaDirs.add(wawonaUIContractsKotlinDir.path)
            }

            val resDirs = mutableListOf("src/main/res")
            resDirs.addAll(existingSkipResDirs.map { it.path })

            manifest.srcFile("src/main/AndroidManifest.xml")
            java.srcDirs(javaDirs)
            res.srcDirs(resDirs)
            assets.srcDirs("src/main/assets")
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // Some Skip artifacts bundle the same native bridge .so multiple times.
            pickFirsts += setOf(
                "**/libSkip*.so",
                "**/libSwift*.so",
            )
        }
    }
}

configurations.all {
    // material3 → material-ripple still requests legacy `animation` / `foundation` coords;
    // substitute to `-android` artifacts so offline Nix + Google Maven resolve cleanly.
    resolutionStrategy.dependencySubstitution {
        substitute(module("androidx.compose.foundation:foundation"))
            .using(module("androidx.compose.foundation:foundation-android:$composeAndroidSubstitutionVersion"))
        substitute(module("androidx.compose.animation:animation"))
            .using(module("androidx.compose.animation:animation-android:$composeAndroidSubstitutionVersion"))
        substitute(module("androidx.compose.material:material"))
            .using(module("androidx.compose.material:material-android:$composeAndroidSubstitutionVersion"))
        substitute(module("androidx.compose.material3.adaptive:adaptive"))
            .using(module("androidx.compose.material3.adaptive:adaptive-android:$material3Adaptive"))
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    // 2.8.7 matches Nix gradle-deps lockfile (full jar graph). 2.9.0 pulled
    // lifecycle-common-java8 without jar entry in lock → offline Nix fail.
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose-android:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-savedstate-android:2.8.7")
    implementation("androidx.savedstate:savedstate-compose-android:1.3.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.customview:customview-poolingcontainer:1.0.0")
    implementation(platform("androidx.compose:compose-bom:$composeBom"))
    implementation("androidx.compose.runtime:runtime-android")
    implementation("androidx.compose.runtime:runtime-saveable-android")
    implementation("androidx.compose.runtime:runtime-retain-android")
    implementation("androidx.compose.ui:ui-android")
    implementation("androidx.compose.ui:ui-graphics-android")
    implementation("androidx.compose.ui:ui-tooling-preview-android")
    implementation("androidx.compose.foundation:foundation-android")
    // SkipUI uses androidx.compose.material.ContentAlpha (Material, not Material3).
    implementation("androidx.compose.material:material-android")
    implementation("androidx.compose.material3:material3-android")
    implementation("androidx.compose.material3:material3-window-size-class-android")
    implementation("androidx.compose.material3.adaptive:adaptive-android:$material3Adaptive")
    implementation("androidx.compose.material:material-icons-extended-android")
    implementation("androidx.compose.animation:animation-android")
    implementation("androidx.navigation3:navigation3-runtime:$androidxNav3")
    implementation("androidx.navigation3:navigation3-ui:$androidxNav3")

    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.fragment:fragment-ktx:1.6.2")
    // SkipFoundation MarkdownNode uses commonmark at runtime; AAR does not embed it.
    implementation("org.commonmark:commonmark:0.24.0")
    implementation("org.commonmark:commonmark-ext-gfm-strikethrough:0.24.0")
    implementation("org.jetbrains.kotlin:kotlin-reflect:$kotlinToolchain")
    skipRoots.forEach { skipRoot ->
        implementation(fileTree(skipRoot) {
            include("**/*.aar")
            if (wawonaUIContractsKotlinOverlayOk) {
                exclude("**/WawonaUIContracts*.aar")
            }
        })
    }
}

configurations.configureEach {
    // Optional transitive modules; Nix offline cache often lacks empty/jar-only edges.
    exclude(mapOf("group" to "androidx.lifecycle", "module" to "lifecycle-common-java8"))
    exclude(mapOf("group" to "androidx.resourceinspection", "module" to "resourceinspection-annotation"))
    exclude(mapOf("group" to "androidx.concurrent", "module" to "concurrent-futures"))
    exclude(mapOf("group" to "com.google.guava", "module" to "listenablefuture"))
    exclude(mapOf("group" to "androidx.profileinstaller", "module" to "profileinstaller"))
}

tasks.named("preBuild").configure {
    dependsOn(ensureSkipArtifacts)
}
