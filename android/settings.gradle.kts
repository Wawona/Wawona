pluginManagement {
    repositories {
        // Prefer Google Maven explicitly: AGP plugin markers live here.
        // gradlePluginPortal() alone misses them in sandboxed MITM builds
        // (cache keyed under dl.google.com, not plugins.gradle.org).
        maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        google()
        maven { url = uri("https://plugins.gradle.org/m2/") }
        mavenCentral()
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
include(":Wawona")
project(":Wawona").projectDir = file("app")
