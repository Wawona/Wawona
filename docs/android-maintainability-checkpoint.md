# Android Module Maintainability Checkpoint

This checkpoint keeps Android Nix modules from drifting into unreviewable
monoliths or reintroducing silent-failure patterns.

## Current Size Budget (line count)

- Default max for `*android.nix`: **400** lines.
- Temporary exceptions:
  - `dependencies/libs/libwayland/android.nix` <= 650
  - `dependencies/libs/waypipe/android.nix` <= 900
  - `dependencies/wawona/android.nix` <= 850

Any new oversized Android module must either:

1. be split into helper modules, or
2. be added here with a short justification and a follow-up refactor issue.

## Silent Failure Policy

- Build-critical Android modules must not use `|| true` in build/install/patch
  paths.
- CI enforces this via `verify-android-maintainability.py`.

## Refactor Direction

- Move repeated Android CMake/linker patterns into toolchain helpers.
- Keep module-local shell phases short and verify required artifacts explicitly.
