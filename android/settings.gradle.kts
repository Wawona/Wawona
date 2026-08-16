pluginManagement {
    repositories {
        // Explicit dl.google.com only. Do not use google()/maven.google.com.
        // Offline MITM caches artifacts under dl.google.com; google() hits
        // maven.google.com first and 301-redirects, which the proxy cannot
        // follow in the Nix sandbox (SocketException → UnknownPluginException).
        maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        maven { url = uri("https://plugins.gradle.org/m2/") }
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Same as pluginManagement: avoid maven.google.com redirect under MITM.
        maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        mavenCentral()
    }
}

rootProject.name = "Wawona"
include(":Wawona")
project(":Wawona").projectDir = file("app")
