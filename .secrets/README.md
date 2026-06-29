# Local release secrets (gitignored contents)

Drop key files here. Only this README and `.gitkeep` are tracked in git.

| File | Source |
|------|--------|
| `AuthKey_XXXXXX.p8` | App Store Connect → Users and Access → Integrations → API → Download key |
| `wawona-upload.keystore` | `keytool -genkeypair` (see `.release-secrets.env.template`) |
| `play-store.json` | Play Console → Setup → API access → service account JSON key |

Paths are referenced from `../.release-secrets.env` (also gitignored).

After filling values:

```bash
./scripts/sync-github-secrets.sh
./scripts/bootstrap-apple-signing.sh
```
