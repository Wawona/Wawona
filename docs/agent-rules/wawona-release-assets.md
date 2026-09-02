# Wawona binary naming (GitHub + stores)

Token order is always **app → calver → platform → arch → [jailbreak-scheme] → [build] → ext**.

| Channel | Pattern | Build in name? |
|---------|---------|----------------|
| **GitHub Release** (`Ship: GitHub assets`, tag `v*`) | `Wawona-{calver}-{platform}-{arch}.{ext}` | No |
| **GitHub Mode B iOS** (same workflow; not Ship: beta) | `Wawona-{calver}-iOS-arm64.tipa` / `…-rootless.deb` / `…-rootful.deb` | No |
| **Store upload** (`Ship: beta` → TestFlight / Play) | `Wawona-{calver}-{platform}-{arch}-{build}.{ext}` | Yes |
| **product-build / Gate** | Short unversioned (`Wawona.apk`, `Wawona.app`, `Wawona-{arch}.AppImage`) | N/A. Rename only at ship boundaries |

Examples (`VERSION=26.8.12`, build `142`):

- GitHub Mode A: `Wawona-26.8.12-macOS-arm64.dmg`, `…-iOS-arm64.ipa`, `…-Android-arm64.apk`, `…-Linux-x86_64.AppImage`, `…-Linux-arm64.AppImage`
- GitHub Mode B iOS: `Wawona-26.8.12-iOS-arm64.tipa`, `…-iOS-arm64-rootless.deb`, `…-iOS-arm64-rootful.deb` (optional `…-roothide.deb`)
- Stores: `Wawona-26.8.12-iOS-arm64-142.ipa` (also `tvOS` / `visionOS`), `Wawona-26.8.12-Android-arm64-142.aab`

Platform tokens: GitHub `macOS` \| `iOS` \| `Android` \| `Linux`; stores also `tvOS` \| `visionOS`. Arch: `arm64` \| `x86_64` (Linux filename maps `aarch64` → `arm64`).

## Mode B iOS wrappers (GitHub + Sileo only)

| Wrapper | File | dpkg `Architecture` | Install prefix |
|---|---|---|---|
| Mode A sideload | `Wawona-{calver}-iOS-arm64.ipa` | n/a | App sandbox |
| TrollStore | `Wawona-{calver}-iOS-arm64.tipa` | n/a | TrollStore app container |
| Sileo **rootless** | `Wawona-{calver}-iOS-arm64-rootless.deb` | `iphoneos-arm64` | `/var/jb` |
| Sileo **rootful** | `Wawona-{calver}-iOS-arm64-rootful.deb` | `iphoneos-arm` | `/` |
| RootHide (optional) | `Wawona-{calver}-iOS-arm64-roothide.deb` | `iphoneos-arm64e` | `jbroot()` |

Jailbreak scheme tokens (`rootless` / `rootful` / `roothide`) are **required** before `.deb`. Rootful and rootless are different builds (DESTDIR, rpath, control), not a renamed tree. Never upload `.tipa` or Mode B `.deb` through Ship: beta / `upload_to_testflight`.

## Hard rejects

- Unversioned GitHub/store ship names: `Wawona.apk`, `Wawona.aab`, `Wawona.deb`, `Wawona-macOS-arm64.dmg`, `Wawona-x86_64.AppImage` on a Release
- Scheme-first store IPAs: `Wawona-iOS-{calver}-{build}.ipa`
- Missing platform or arch on a ship basename
- One `.deb` that claims both rootful and rootless
- Passing a product-build short name straight to `gh release upload`, `upload_to_testflight`, or `upload_to_play_store` without renaming
- Mode B entitlements in a store IPA

product-build short names are fine **inside** Gate artifacts only.

Docs: [`../ci.md`](../ci.md), https://wawona.io/docs/prebuilt-naming/
