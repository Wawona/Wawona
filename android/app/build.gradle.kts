plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.aspauldingcode.wawona"
    compileSdk = 36
    buildToolsVersion = "36.1.0"
    ndkVersion = "29.0.14206865"

    defaultConfig {
        applicationId = "com.aspauldingcode.wawona"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        ndk {
            val requestedAbi = (System.getenv("WAWONA_ANDROID_ABI") ?: "arm64-v8a").trim()
            abiFilters.clear()
            abiFilters += requestedAbi
        }

        externalNativeBuild {
            cmake {
                cppFlags("-fPIC")

                fun prop(name: String): String =
                    (project.findProperty(name) as? String)?.trim().orEmpty()

                // When building under Nix, DEP_INCLUDES is populated in the environment.
                // We pass it to CMake as a property so it can include external Nix paths.
                val nixIncludes =
                    (System.getenv("DEP_INCLUDES") ?: prop("wawona.nixDepIncludes")).trim()
                if (nixIncludes.isNotEmpty()) {
                    arguments("-DNIX_DEP_INCLUDES=${nixIncludes}")
                }

                // Linker paths for Nix external dependencies
                val nixLibs =
                    (System.getenv("DEP_LIBS") ?: prop("wawona.nixDepLibs")).trim()
                if (nixLibs.isNotEmpty()) {
                    arguments("-DNIX_DEP_LIBS=${nixLibs}")
                }

                // Rust Backend Object
                val rustLib =
                    (System.getenv("RUST_BACKEND_LIB") ?: prop("wawona.rustBackendLib")).trim()
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

    buildFeatures {
        compose = true
    }

    packaging {
        jniLibs {
            // AGP upgrade path: replace manifest extractNativeLibs with DSL.
            useLegacyPackaging = true
        }
    }

    sourceSets {
        getByName("main") {
            kotlin.directories += "src/main/kotlin"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.lifecycle") {
            useVersion("2.10.0")
            because("Pin lifecycle to versions available in the Nix offline cache.")
        }
        if (requested.group == "androidx.savedstate") {
            useVersion("1.4.0")
            because("Pin savedstate artifacts to versions present in the Nix offline cache.")
        }
        if (requested.group == "androidx.annotation" && requested.name == "annotation-experimental") {
            useVersion("1.5.1")
            because("Pin annotation-experimental to a version present in the Nix offline cache.")
        }
        if (requested.group == "androidx.activity") {
            useVersion("1.12.0")
            because("Pin activity artifacts to versions present in the Nix offline cache.")
        }
        if (requested.group == "androidx.core" && requested.name == "core-viewtree") {
            useVersion("1.0.0")
            because("Pin core-viewtree to the mirrored version in the Nix offline cache.")
        }
        if (requested.group == "androidx.core" && requested.name != "core-viewtree") {
            useVersion("1.16.0")
            because("Pin core artifacts to versions present in the Nix offline cache.")
        }
        if (requested.group == "androidx.navigationevent") {
            useVersion("1.0.2")
            because("Pin navigationevent artifacts to versions present in the Nix offline cache.")
        }
    }
    resolutionStrategy.dependencySubstitution {
        substitute(module("androidx.compose.foundation:foundation"))
            .using(module("androidx.compose.foundation:foundation-android:1.10.5"))
        substitute(module("androidx.compose.animation:animation"))
            .using(module("androidx.compose.animation:animation-android:1.10.5"))
        substitute(module("androidx.compose.material:material"))
            .using(module("androidx.compose.material:material-android:1.10.5"))
        substitute(module("androidx.compose.material3.adaptive:adaptive"))
            .using(module("androidx.compose.material3.adaptive:adaptive-android:1.2.0"))
    }
}

dependencies {
    val composeBom = "2026.03.00"
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.core:core:1.16.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.activity:activity-compose:1.12.0")
    implementation(platform("androidx.compose:compose-bom:$composeBom"))
    implementation("androidx.compose.runtime:runtime-android")
    implementation("androidx.compose.ui:ui-android")
    implementation("androidx.compose.ui:ui-graphics-android")
    implementation("androidx.compose.ui:ui-tooling-preview-android")
    implementation("androidx.compose.foundation:foundation-android")
    implementation("androidx.compose.material:material-android")
    implementation("androidx.compose.material3:material3-android")
    implementation("androidx.compose.material:material-icons-extended-android")
    implementation("androidx.compose.animation:animation-android")
    
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.fragment:fragment-ktx:1.6.2")
}

configurations.configureEach {
    exclude(mapOf("group" to "androidx.lifecycle", "module" to "lifecycle-common-java8"))
    exclude(mapOf("group" to "androidx.resourceinspection", "module" to "resourceinspection-annotation"))
    exclude(mapOf("group" to "androidx.concurrent", "module" to "concurrent-futures"))
    exclude(mapOf("group" to "com.google.guava", "module" to "listenablefuture"))
    exclude(mapOf("group" to "androidx.profileinstaller", "module" to "profileinstaller"))
}

// Bypassing the AAR metadata check task which fails in the Nix sandbox
tasks.withType<com.android.build.gradle.internal.tasks.CheckAarMetadataTask>().configureEach {
    enabled = false
}
