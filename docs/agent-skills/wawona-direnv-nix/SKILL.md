---
name: wawona-direnv-nix
description: Reproducible Wawona dev shells and local Apple signing boundaries.
---

# Direnv and Nix

Use committed `.envrc` `use flake` and ignored `.envrc.local`. Keep signing
inputs out of Nix and Git. Signed IPA exports require explicit `--impure` and
all signing inputs, not just `TEAM_ID`.
