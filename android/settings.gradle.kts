pluginManagement {
    repositories {
        google()
        maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        maven { url = uri("https://plugins.gradle.org/m2/") }
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
include(":Wawona")
project(":Wawona").projectDir = file("app")
