# APT repository

`repo.wawona.io` APT is Mode B only. The App Store app must not download
`.deb` packages or other executables. Wasm packages on `/wasm/v1` are the
store channel and are unrelated to this CLI.

## Intended groups

When Mode B binaries exist, group them instead of shipping one package per
command:

| Package | Contents |
|---|---|
| `wawona-darwin-tools` | container-safe tools only if a jailbreak build differs from the app |
| `wawona-uikit-tools` | uikittools-ng commands |
| `wawona-launch-tools` | Procursus launchctl `v1.2.0` (XPC to host launchd) |
| `wawona-security-tools` | ldid, kept AGPL-separate |

Dependencies that Procursus already ships (coreutils, zsh, curl) stay
Procursus dependencies. Wawona packages should `Depends:` on them rather than
vendoring a second copy.

## Metadata

`Packages`, `Packages.gz`, and `Release` belong to the repo host, generated
from real `.deb` files. This tree does not publish empty repository metadata.

Architectures to support when packaging starts: `iphoneos-arm64` (rootless),
`iphoneos-arm` (rootful), and `iphoneos-arm64e` where a roothide build is
actually produced. Path prefixes go through `JailbreakEnvironment`.

## Interop

A jailbreak that already has a Procursus bootstrap can add the Wawona APT
source beside it. Package names must not replace Procursus `defaults` or
`launchctl` until the Wawona package is the intended provider. If both exist,
document a `Conflicts` or install the Wawona names with a distinct package
name.
