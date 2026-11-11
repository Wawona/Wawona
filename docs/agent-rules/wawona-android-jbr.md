# Android Gradle uses JBR Java

Wawona Android Gradle and Android Studio must run on **JetBrains Runtime
(JBR) 21**, not nixpkgs OpenJDK, Temurin, or Zulu.

## Local / Android Studio

Pin Project + Gradle JVM to the IDE JDK named `21` (Studio embedded JBR).

- `.idea/misc.xml`: `project-jdk-name="21"`
- `.idea/gradle.xml`: `gradleJvm=21`
- Local builds: `cargo xtask build android` resolves Studio JBR 21 when `JAVA_HOME` is unset

Do not export Nix `JAVA_HOME` into Android Studio. That is `#GRADLE_LOCAL_JAVA_HOME`
or a stale OpenJDK path. Symptom: **Invalid Gradle JDK configuration**.

Override path: `ANDROID_STUDIO_JBR`.

## Where Gradle runs

| Host | Gradle JVM |
|---|---|
| Android Studio, `cargo xtask build android` locally | Embedded Studio JBR 21 |
| CI (`setup-xtask` with `android: true`) | `actions/setup-java`, distribution `jetbrains`, 21 |

Nix builds only the Android dependency slice (`.#deps-android`); it runs no
Gradle.

## Hard rejects

- Driving Android Studio or local `./gradlew` with nixpkgs `jdk17` / `jdk21`
- `#USE_PROJECT_JDK` without `project-jdk-name`, or `#GRADLE_LOCAL_JAVA_HOME`
- Committing a machine-specific `org.gradle.java.home` into `android/gradle.properties`

Cursor rule: `wawona-android-jbr`. See `docs/android-upgrade-guardrails.md`.
