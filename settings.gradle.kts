// Nix builds offline: `-Pwawona.maven=<file:// URLs>` replaces every remote
// repository with its mirror. Explicit dl.google.com, not google(): google()
// goes through maven.google.com, a redirect the mirror does not have.
pluginManagement {
    repositories {
        val mirrors = providers.gradleProperty("wawona.maven").orNull
        if (mirrors != null) {
            mirrors.split(' ').filter { it.isNotBlank() }.forEach { maven { url = uri(it) } }
        } else {
            maven { url = uri("https://dl.google.com/dl/android/maven2/") }
            gradlePluginPortal()
            mavenCentral()
        }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        val mirrors = providers.gradleProperty("wawona.maven").orNull
        if (mirrors != null) {
            mirrors.split(' ').filter { it.isNotBlank() }.forEach { maven { url = uri(it) } }
        } else {
            maven { url = uri("https://dl.google.com/dl/android/maven2/") }
            mavenCentral()
        }
    }
}

rootProject.name = "Wawona"
include(":Wawona")
project(":Wawona").projectDir = file("android/app")
