# FlakeHub registry (versioned flake refs)

Wawona org flakes are **published** to FlakeHub. `wwn-*` DAG repos use
**rolling** `0.1.<commit-count>` on their tracked branch. **Wawona** also
publishes **CalVer tags** (`vYY.M.D` → SemVer `YY.M.D`, same as
[`VERSION`](../VERSION) / GitHub Releases).

Consumers pin `https://flakehub.com/f/Wawona/<repo>/*`; `flake.lock` records
the resolved tarball. `*` is the highest SemVer: a Wawona tag `26.8.12`
outranks rolling `0.1.N`. This is separate from the **binary cache**.

Companion: [`flakehub-cache.md`](./flakehub-cache.md).
Upstream: [Publishing to FlakeHub](https://docs.determinate.systems/flakehub/publishing/).
Org page: [flakehub.com/org/Wawona](https://flakehub.com/org/Wawona).

## Cache vs registry

| | FlakeHub Cache | FlakeHub Releases (this doc) |
|---|---|---|
| What | Store paths (`cache.flakehub.com`) | Versioned flake tarballs |
| CI action | `flakehub-cache-action@v3` on build jobs | `flakehub-push` in `flakehub-publish.yml` |
| UI “releases” | Does not create them | `fh list releases Wawona/<repo>` |
| Input URL | Unchanged (`github:` still caches) | `https://flakehub.com/f/Wawona/<repo>/*` |

The GitHub App listing a flake under the org is **discovery**, not a release.
Until `flakehub-push` succeeds, `fh list releases` is empty and convert is
blocked.

## URL form

Hand-edit Wawona org edges only. Do **not** blind-run `fh convert` — it
rewrites third-party inputs incorrectly (observed mangling of `rust-overlay`,
`crate2nix`, `microvm`, `nix-xcodeenvtests`).

```nix
wwn-toolchain.url = "https://flakehub.com/f/Wawona/wwn-toolchain/*";
wwn-toolchain.inputs.nixpkgs.follows = "nixpkgs";
```

Keep existing `follows` (nixpkgs, rust-overlay, peer `wwn-*`). DAG layers are
unchanged; see [`wwn-repo-dag.md`](./wwn-repo-dag.md).

## Publish workflow

Each GitHub-hosted flake runs [`.github/workflows/flakehub-publish.yml`](../.github/workflows/flakehub-publish.yml):

- **Branches:** `development` where consumers historically pinned that branch
  (`wwn-toolchain`, `wwn-iland`, `wwn-kmscube`, `wwn-weston`, `wwn-waypipe`,
  `wwn-phoon-rs`, `wwn-neovim`, `wwn-niri`, `Wawona`); `main` otherwise.
- **Tags (Wawona):** `vYY.M.D` publishes SemVer `YY.M.D` (`rolling: false`).
  Existing tags are backfilled via **workflow_dispatch** `tag=` (they predate
  this workflow, so a tag push did not run it). `wwn-*` stay rolling-only
  until they grow CalVer tags.
- **Visibility:** `public`.
- **`include-output-paths`:** `false`. Inspecting every output on
  `ubuntu-latest` fails without the Android SDK / on Darwin-only attrs.
  NAR paths come from FlakeHub Cache build jobs, not from this workflow.
- One tracked branch per repo (do not publish rolling from both `main` and
  `development` — interleaved commit-count versions).

Rolling versions are `0.1.<commit-count>+rev-<sha>`. They track **publish CI**,
not a git branch name: a tip that never hits this workflow will not appear as
`*`.

`flakehub-push` also runs `nix flake show --all-systems`. Nixpkgs 26.11 throws
on `x86_64-darwin`; Wawona / anowaW / phoon-rs omit Intel Darwin from
`packages`/`apps`. Wawona’s publish job runs on **macos-26** with relaxed
sandbox + FlakeHub Cache so Android SDK IFD can succeed and the tarball is
the real flake (not an empty stub).

## Verify

```bash
fh login   # or determinate-nixd login
fh list releases Wawona/wwn-toolchain
nix flake metadata   # Wawona lock nodes should be type=tarball on api.flakehub.com
```

Verify scripts that clone inputs from `flake.lock` (e.g.
[`checkout-flake-inputs.sh`](../.github/scripts/checkout-flake-inputs.sh)) must
treat FlakeHub tarball locks as `Wawona/<node>` + `locked.rev` when `owner`/`repo`
are absent.
