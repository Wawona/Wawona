# Wawona binary naming (GitHub + stores)

Token order is always **app → calver → platform → arch → [build] → ext**.

| Channel | Pattern | Build in name? |
|---------|---------|----------------|
| **GitHub Release** (`Ship: GitHub assets`, tag `v*`) | `Wawona-{calver}-{platform}-{arch}.{ext}` | No |
| **Store upload** (`Ship: beta` → TestFlight / Play) | `Wawona-{calver}-{platform}-{arch}-{build}.{ext}` | Yes |
| **product-build / Gate** | Short unversioned (`Wawona.apk`, `Wawona.app`, `Wawona-{arch}.AppImage`) | N/A. Rename only at ship boundaries |

Examples (`VERSION=26.8.12`, build `142`):

- GitHub: `Wawona-26.8.12-macOS-arm64.dmg`, `…-iOS-arm64.ipa`, `…-Android-arm64.apk`, `…-Linux-x86_64.AppImage`, `…-Linux-arm64.AppImage`
- Stores: `Wawona-26.8.12-iOS-arm64-142.ipa` (also `tvOS` / `visionOS`), `Wawona-26.8.12-Android-arm64-142.aab`

Platform tokens: GitHub `macOS` \| `iOS` \| `Android` \| `Linux`; stores also `tvOS` \| `visionOS`. Arch: `arm64` \| `x86_64` (Linux filename maps `aarch64` → `arm64`).

## macOS GitHub DMG contents

Volume root is **drag-install**:

| On the DMG | Not on the DMG |
|---|---|
| `Wawona.app` (Developer ID signed + notarized) | `WawonaAgent.pkg` |
| `/Applications` symlink | PrefPane |
| `README.txt` (thank-you + install notes) | |

Users drag `Wawona.app` to Applications. Launch Agents / Login Item install from
Settings → Permissions (or the first-launch offer). Optional maintainer pkg
stays off the release volume (`scripts/macos-launch-agent-pkg.sh` for lab use).

## Hard rejects

- Unversioned GitHub/store ship names: `Wawona.apk`, `Wawona.aab`, `Wawona-macOS-arm64.dmg`, `Wawona-x86_64.AppImage` on a Release
- Scheme-first store IPAs: `Wawona-iOS-{calver}-{build}.ipa`
- Missing platform or arch on a ship basename
- Passing a product-build short name straight to `gh release upload`, `upload_to_testflight`, or `upload_to_play_store` without renaming
- Shipping `WawonaAgent.pkg` on the GitHub Release DMG (drag-install only)

product-build short names are fine **inside** Gate artifacts only.

Docs: [`../ci.md`](../ci.md), https://wawona.io/docs/prebuilt-naming/
