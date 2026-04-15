plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
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
    }

    buildFeatures {
        compose = true
    }

    sourceSets {
        getByName("main") {
            manifest.srcFile("src/main/AndroidManifest.xml")
            java.srcDirs("src/main/java", "src/main/kotlin")
            res.srcDirs("src/main/res")
            assets.srcDirs("src/main/assets")
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.lifecycle") {
            useVersion("2.8.7")
            because("Pin lifecycle to versions available in the Nix offline cache.")
        }
        if (requested.group == "androidx.savedstate") {
            useVersion("1.3.0")
            because("Pin savedstate artifacts to cached versions.")
        }
        if (requested.group == "androidx.core" && requested.name == "core") {
            useVersion("1.15.0")
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
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.core:core:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")
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
