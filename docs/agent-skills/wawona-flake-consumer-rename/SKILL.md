---
name: wawona-flake-consumer-rename
description: >-
  After renaming a flake input or GitHub repo (e.g. wwn-iland to iLand /
  iland), update every consumer tip, flake.lock, and follows keys before
  claiming Wawona eval green. Use when flake outputs complain about a
  missing old input name, FlakeHub pins lag GitHub, or lock pins a pre-rename
  sibling tip.
---

# Flake consumer rename (cascade)

Canonical DAG: `wawona-repo-dag`, `docs/wwn-repo-dag.md`. Registry **keys**
(e.g. `iland` package name) may stay stable while the **flake input** and
GitHub repo rename.

## Proven failure (2026-10-12)

Renamed `Wawona/wwn-iland` → `Wawona/iLand`, input `iland`. Wawona tip
followed `iland`, but locked `wwn-waypipe` still had:

```text
error: function 'outputs' called without required argument 'wwn-iland'
at «github:Wawona/wwn-waypipe/<old-rev»/flake.nix
```

Lock was on a pre-rename waypipe tip. FlakeHub `iLand/*` can also lag
GitHub `development`.

## Checklist (same change set)

1. **Rename source flake** outputs + docs to the new input name. Push
   `development`.
2. **Every consumer** that takes that input: rename in `flake.nix`
   `inputs` and `outputs = { … }`, push each consumer tip.
3. **Wawona (L4)** lock bump:
   ```bash
   nix flake lock --update-input <consumer>   # e.g. wwn-waypipe wwn-igetty
   # plus explicit follows so FlakeHub/old nested locks cannot win:
   #   wwn-waypipe.inputs.iland.follows = "iland";
   ```
4. **Prove** before UI work:
   ```bash
   nix flake metadata . | rg -i 'iland|waypipe|wwn-iland'
   # expect: iland → github:Wawona/iLand/<tip>
   # expect: wwn-waypipe/iland follows input 'iland'
   # never: required argument 'wwn-iland'
   ```
5. Prefer `github:Wawona/<repo>/development` for L1/L3′ while FlakeHub
   republishes. Do not leave consumers on FlakeHub pins that still name
   the old repo.

## Hard rejects

❌ Bump only Wawona `iland` lock and leave waypipe/igetty on old tips  
❌ Claim rename done while eval still asks for `wwn-iland`  
❌ Rely on FlakeHub alone the day of a GitHub rename  
❌ Invert DAG (L0 importing L1) while renaming  

## Related

- Skill `wawona-ios-sim-runtime` (next failures after eval is green)
- Skill `wawona-package` (LIBC / TEXT / GPU before rebuilds)
- Rule `wawona-local-before-ci` (prove link/eval locally)
