# Direnv and Nix reproducibility

Use the committed flake and `flake.lock` through `.envrc` `use flake`. Local
credentials belong only in ignored `.envrc.local`, loaded before the flake.
Never put signing secrets in Nix expressions, derivations, tracked `.envrc`,
or logs. Signed outputs use `nix build --impure` only after the local signing
environment is present.

`TEAM_ID` alone is insufficient for IPA export. Preserve the release check for
certificate, password, provisioning profile, signing method, and identity.
