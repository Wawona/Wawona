# Release secrets (tier 0 maintainers)

Audience: **tier 0** — Wawona maintainers who ship TestFlight / Play / signed
releases (Alex Spaulding today; future core maintainers). Contributors do **not**
need this document to build or test the public tree.

## Public vs private

| Lives in **public** `Wawona/Wawona` | Lives only in **private** vaults |
| ----------------------------------- | -------------------------------- |
| [`secretspec.toml`](../../secretspec.toml) — secret **names** | GPG ciphertext in pass |
| Scripts (`release-env.sh`, `sync-github-secrets.sh`, migrate) | GPG private key + passphrase |
| This doc (procedural) | Apple/Play plaintext values |
| GitHub Environment secret *slots* on `release-beta` | Values synced into those slots |

Forking the public repo does **not** grant release secrets. Values live in a
**private** password-store on Alex’s personal GitHub:

- Remote: `git@github.com:aspauldingcode/.password-store.git`
- Paths:
  - `secretspec/wawona/release-apple/<KEY>`
  - `secretspec/wawona/release-android/<KEY>`

Never share a GPG **private** key. Each maintainer has their own keypair; pass
encrypts to a recipient list of **public** keys (`.gpg-id` per directory).

## Architecture

```
Public Wawona                    Private aspauldingcode/.password-store
┌─────────────────────┐          ┌────────────────────────────────────┐
│ secretspec.toml     │          │ secretspec/wawona/release-apple/   │
│ scripts/release-env │──pass───▶│ secretspec/wawona/release-android/ │
│ sync-github-secrets │          │ (.gpg-id = tier 0 fingerprints)    │
└─────────┬───────────┘          └────────────────────────────────────┘
          │ gh secret set
          ▼
┌─────────────────────┐          Host (dendritic / sops-nix)
│ GitHub env          │          GPG key + passphrase → gpg-agent
│ release-beta        │◀───────── unlocks pass for local/sync
│ (CI profile: env)   │
└─────────────────────┘
```

- **SecretSpec** — declares what the app needs; `secretspec run` injects env.
- **pass** — encrypted store; team ACL via `.gpg-id` (no private-key sharing).
- **sops-nix** (host / dendritic) — bootstraps GPG on maintainer machines only.
  Do **not** put MATCH/Play ciphertext into public Wawona sops files.
- **GitHub `release-beta`** — CI runtime; Actions use `SECRETSPEC_PROFILE=ci` + `env`.

## Profiles

| Profile | Provider | Use |
|---------|----------|-----|
| `local` | `pass_apple` / `pass_android` | Local Fastlane (`./scripts/release-env.sh ...`) |
| `sync` | pass | `./scripts/sync-github-secrets.sh` |
| `ci-apple` | `env` | Release Beta Apple job |
| `ci-android` | `env` | Release Beta Android job |
| `ci` | `env` (all optional) | Combined env when both platforms are present |

## One-time bootstrap (new tier-0 machine)

1. Host GPG via dendritic/sops-nix (existing pass + gpg-agent setup).
2. Clone the private store (if not already `~/.password-store`):

   ```bash
   git clone git@github.com:aspauldingcode/.password-store.git ~/.password-store
   ```

3. Confirm unlock: `pass show secretspec/wawona/release-apple/TEAM_ID`
4. In Wawona:

   ```bash
   nix develop .#release
   secretspec check -P local
   ./scripts/release-env.sh fastlane validate_env
   ```

### Migrating from legacy `.release-secrets.env`

If you still have a filled `.release-secrets.env` + `.secrets/*`:

```bash
./scripts/migrate-release-secrets-to-pass.sh
(cd "$PASSWORD_STORE_DIR" && pass git push)
./scripts/sync-github-secrets.sh
```

Then stop sourcing the dotenv file.

## Day-2 operations

```bash
# Local TestFlight / Play
./scripts/release-env.sh fastlane ios beta
./scripts/release-env.sh fastlane android beta

# Push secrets to GitHub Environment release-beta
./scripts/sync-github-secrets.sh            # full
./scripts/sync-github-secrets.sh --apple-only

# First-time / regenerate match certs
./scripts/bootstrap-apple-signing.sh
# or: MATCH_FORCE=1 ./scripts/release-env.sh fastlane regenerate_signing
```

IPA builds use **match + gym** (not `nix build …-ipa`). Nix still runs
`xcodegen` and the Xcode `xcode-prebuild.sh` Rust phase during archive.

## ACL (tier 0 vs helpers)

| Tier | Access |
|------|--------|
| **0** (maintainers) | Both `release-apple` and `release-android` `.gpg-id`; sync to GitHub; this doc |
| **1** (optional later) | Subtree-only recipient on one folder |
| Everyone else | Names in `secretspec.toml` only; release lanes fail closed |

### Onboard a tier-0 maintainer

1. They generate a GPG key and send you the **public** fingerprint / key.
2. `gpg --import` their public key.
3. Add fingerprint to:
   - `secretspec/wawona/.gpg-id`
   - `secretspec/wawona/release-apple/.gpg-id`
   - `secretspec/wawona/release-android/.gpg-id`
4. Re-encrypt: `pass init -p secretspec/wawona/release-apple <fps…>` (and android).
5. Invite them to the **private** `.password-store` GitHub repo (read).
6. They `pass git pull` and `secretspec check -P local`.

### Offboard

1. Remove their fingerprint from the relevant `.gpg-id` files.
2. Re-encrypt those subtrees.
3. Remove their GitHub collaborator access on `.password-store`.
4. If compromise suspected: rotate MATCH password, ASC key, Play JSON, keystore.

**Never** share one org/maintainer GPG private key among humans.

## Rotation checklist

| Secret | Rotate how |
|--------|------------|
| `MATCH_PASSWORD` | New passphrase → re-encrypt match repo / `fastlane match` → `pass insert` → sync |
| `ASC_P8` / key IDs | New ASC API key → pass → sync → revoke old key in ASC |
| `APPLE_SIGNING_PAT` | New fine-grained PAT on `apple-signing` → pass → sync |
| Play JSON | New SA key in GCP/Play → pass → sync → disable old key |
| Upload keystore | Rare; Play upload-key reset process → pass → sync |

## Related docs

- Release Beta workflow: [`../ci.md`](../ci.md)
- Distribution / TestFlight status: [`../distribution-ops.md`](../distribution-ops.md)
- Dendritic pass + SecretSpec (host pattern): `/etc/nix-darwin/.dotfiles/docs/pass-secretspec.md` (local machines)
