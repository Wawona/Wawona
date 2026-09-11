# Android Gradle uses JBR Java

Wawona Android Gradle and Android Studio must run on **JetBrains Runtime
(JBR) 21**, not nixpkgs OpenJDK, Temurin, or Zulu.

## Local / Android Studio

Pin Project + Gradle JVM to the IDE JDK named `21` (Studio embedded JBR).

- `android/studio/misc.xml`: `project-jdk-name="21"`
- `android/studio/gradle.xml`: `gradleJvm=21`
- `gradlegen` writes `org.gradle.java.home` to the generated project when
  Studio JBR is on disk (`Contents/jbr/Contents/Home`)
- Local `./gradlew`: `source scripts/lib/android-jbr.sh && wawona_android_export_jbr`

Do not export Nix `JAVA_HOME` into Android Studio. That is `#GRADLE_LOCAL_JAVA_HOME`
or a stale OpenJDK path. Symptom: **Invalid Gradle JDK configuration**.

Override path: `ANDROID_STUDIO_JBR`.

## Nix

| Host | Gradle JVM |
|---|---|
| Linux CI / `.#wawona-android` | `jetbrains.jdk-no-jcef-21` (JBR 21, no JCEF) |
| Darwin Nix sandbox | OpenJDK 17. nixpkgs `jetbrains.jdk*` is Linux-only |
| Darwin local Studio / `.#wawona-android-project` | Embedded Studio JBR 21 |

## Hard rejects

- Driving Android Studio or local `./gradlew` with nixpkgs `jdk17` / `jdk21`
- `#USE_PROJECT_JDK` without `project-jdk-name`, or `#GRADLE_LOCAL_JAVA_HOME`
- Committing a machine-specific `org.gradle.java.home` into `android/gradle.properties`

Cursor rule: `wawona-android-jbr`. See `docs/android-upgrade-guardrails.md`.
