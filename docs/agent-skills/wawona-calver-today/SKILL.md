---
name: wawona-calver-today
description: >-
  Before building Wawona products, ensure VERSION is today's CalVer YY.M.D.
  Fail closed on mismatch. Use when bumping versions, tipa/IPA builds, or
  CalVer/CI naming.
---

# CalVer today

Open rule `wawona-calver-today` and
`docs/agent-rules/wawona-calver-today.md`.

```bash
bash .github/scripts/verify-calver-today.sh
# bump VERSION + Cargo.toml + Cargo.lock to $(date in America/Los_Angeles as YY.M.D)
```

Hard reject: product build on stale CalVer without `WAWONA_ALLOW_STALE_CALVER=1`.
