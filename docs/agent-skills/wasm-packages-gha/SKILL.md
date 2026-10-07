---
name: wasm-packages-gha
description: Build WASI packages for repo.wawona.io/wasm on GitHub Actions. Use when adding recipes, running build-wasm.yml, or publishing catalog blobs.
---

# wasm-packages GHA builds

Production path: **GitHub Actions** on `ubuntu-24.04`. Not a laptop.

| Piece | Path |
|-------|------|
| Recipes | `recipes.json` + `packages/<name>/` |
| Build | `.github/workflows/build-wasm.yml` |
| Publish | `.github/workflows/publish-to-repo.yml` (`WAWONA_REPO_TOKEN`) |
| Catalog | `repo.wawona.io` `/wasm/v1` |

```bash
gh workflow run build-wasm.yml --repo Wawona/wasm-packages
```

ABI / phase order: `repo.wawona.io/docs/wasm-abi.md`.
Org catalogs skill: `repo-wawona-io-catalogs`.

## Never

- Publish laptop-built `.wasm` as production
- Revive `nixpkgs2wasi`
- Claim WASIX runs on store Pulley
- Put build recipes only in `repo.wawona.io` (catalog host stays thin)
