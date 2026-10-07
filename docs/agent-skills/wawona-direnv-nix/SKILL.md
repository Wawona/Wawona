---
name: wawona-direnv-nix
description: Reproducible Wawona dev shells and local Apple signing boundaries.
---

# Direnv and Nix

Use committed `.envrc` `use flake` and ignored `.envrc.local`. Keep signing
inputs out of Nix and Git. Signed IPA exports require explicit `--impure` and
all signing inputs, not just `TEAM_ID`.

## Local Xcode source filtering (2026-09-30)

A path-based full app build copied ignored `build/` and `.derivedData*` trees
into WawonaXcodeProject. Stale DerivedSources links then failed
`noBrokenSymlinks` before app linking. Filter local build outputs before
source staging; never disable the fixup check. Exclude root `build`, `target`,
`.build`, `.direnv`, plus `.cache`, `.git`, `.derivedData*`, and `result` links.
Keep untracked product sources in local builds; git flakes omit them.
Host Swift Keychain tests need access outside the execution sandbox. All 40
passed with that access; the sandboxed attempt failed secret round-trips.

Also exclude root `.nix-deps`, `.artifacts`, `.agent-device` and
`Wawona-gradle-project` when staging a local product source. These generated
outputs added approximately 11 GB to a measured source snapshot. Preserve
the original files and untracked product sources; do not disable fixup checks.
