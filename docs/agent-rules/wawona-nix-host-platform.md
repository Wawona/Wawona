# Nix: detect OS via hostPlatform (not stdenv.isDarwin)

`nixpkgs` deprecates `stdenv.isDarwin` / `stdenv.isLinux` (and the same names
on `stdenvNoCC`). Evals print:

```text
evaluation warning: stdenv.isDarwin is deprecated, use stdenv.hostPlatform.isDarwin instead
evaluation warning: stdenv.isLinux is deprecated, use stdenv.hostPlatform.isLinux instead
```

**Always write the `hostPlatform` form** in Wawona and `wwn-*` flakes, overlays,
and recipes. `hostPlatform` is the system the derivation **runs on**. Use
`buildPlatform` only when the check is about the **builder** (cross). Do not
use `targetPlatform` for ordinary Darwin/Linux package conditionals.

## Use this

```nix
# ✅
stdenv.hostPlatform.isDarwin
stdenv.hostPlatform.isLinux
stdenv.hostPlatform.isAarch64
stdenv.hostPlatform.isx86_64
pkgs.stdenv.hostPlatform.isDarwin
lib.optional stdenv.hostPlatform.isDarwin [ ... ]
```

## Not this

```nix
# ❌  (eval warning; do not add; replace on touch)
stdenv.isDarwin
stdenv.isLinux
pkgs.stdenv.isDarwin
stdenvNoCC.isLinux
```

Same rename for other `stdenv.is*` OS/CPU aliases (`isAarch64`, `isi686`, …):
`stdenv.hostPlatform.isAarch64`, not `stdenv.isAarch64`.

Prefer `hostPlatform.isDarwin` over string compares like
`stdenv.system == "aarch64-darwin"` unless you truly need the full system
triple.

## Scope

New Nix and any file you already edit. Do not drive-by rewrite the whole
tree in the same change unless the task is that cleanup.

Cursor: `.cursor/rules/wawona-nix-host-platform.mdc`.
