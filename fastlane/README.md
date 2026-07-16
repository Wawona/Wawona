fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### sync_version

```sh
[bundle exec] fastlane sync_version
```

Sync version from VERSION file to Cargo.toml and Android build.gradle.kts

### validate_env

```sh
[bundle exec] fastlane validate_env
```

Verify release environment (Apple credentials)

### regenerate_signing

```sh
[bundle exec] fastlane regenerate_signing
```

Enable iCloud on App IDs and force-regenerate App Store match profiles

### beta

```sh
[bundle exec] fastlane beta
```

Upload Apple + Android beta builds

----


## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload iPhone, iPad, Apple TV, Apple Vision Pro, and Apple Watch to TestFlight (excludes macOS)

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit iOS builds for App Store review

----


## Android

### android beta

```sh
[bundle exec] fastlane android beta
```

Upload Android AAB to Play internal track

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
