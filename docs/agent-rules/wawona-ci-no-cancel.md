# CI: never cancel tip gates

Agents must not clear the Actions queue with `gh run cancel`.

## Why

WIP workflows use **soft supersede** ([`ci-require-branch-tip.sh`](../../.github/scripts/ci-require-branch-tip.sh)): obsolete SHAs skip expensive jobs and exit success. Cancelling Gate: packages, Gate: products, or Verification creates grey Cancelled noise and can leave the tip without a completed promote signal.

## Do

- Watch runs: `gh run watch <id> --exit-status`
- Re-run a tip: `gh workflow run … --ref development` or push a real fix
- Promote only when Verification report, Gate: packages, and Gate: products are **success** on that tip

## Do not

- `gh run cancel` on Gate / Verification / Ship to “protect” another workflow
- Treat superseded (skipped) jobs as product failures
- Promote `development` → `master` without a green full product matrix

Canonical: [`docs/ci.md`](../ci.md). Cursor rule: `wawona-ci-no-cancel`.
