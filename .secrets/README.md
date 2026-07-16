# Local release secrets (legacy / migration only)

**Preferred path (tier 0):** SecretSpec + private pass store — see
[`docs/maintainers/secrets.md`](../docs/maintainers/secrets.md).

This directory may still hold key files during migration. Only this README and
`.gitkeep` are tracked in git. Never commit `.p8`, keystores, or Play JSON.

| Legacy file | Migrates to pass path |
|-------------|------------------------|
| `AuthKey_*.p8` / `Authkey.p8` | `secretspec/wawona/release-apple/ASC_P8` |
| `wawona-upload.keystore` | `secretspec/wawona/release-android/ANDROID_KEYSTORE_BASE64` |
| `play-store.json` | `secretspec/wawona/release-android/PLAY_STORE_JSON_KEY` |

```bash
./scripts/migrate-release-secrets-to-pass.sh
./scripts/sync-github-secrets.sh
./scripts/release-env.sh fastlane validate_env
```
