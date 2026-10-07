# Native over WASI / WASIX (no duplicate packaging)

Authority: product preference native-first (`docs/wasm-wasi.md`),
`wwn-coreutils` / `wwn_safe_subset[]` in `wawona-dispatch.c`,
`wasm-packages/scripts/native-all-targets.txt`.

## Hard rule

If a CLI (or equivalent capability) already ships as a **native** port on
**every** Wawona product target, do **not** also package it for WASI P1,
WASIX, or `/wasm/v1`.

Native shell uutils (safe subset) wins over `wasm-packages` / wasinix twins
of the same name.

## Do

- Keep `wwn-coreutils` / in-process uutils as the shell CLI path.
- Grow wasm only for software without an all-target native twin. Real ports
  only: store P1 via `wasm-packages`, POSIX-heavy CLIs via `wasinix` (WASIX).
  See `wawona-wasm-cli-ports`. Never stub `jq`/`grep`/`sed` as catalog filler.
- Keep `scripts/native-all-targets.txt` in sync with `wwn_safe_subset[]`.
- Fail `sync-recipes-from-allowlist.py` if an **active** allowlist name is
  on that list. Prune those names from the live index on publish.

## Hard rejects

- Wasm `cat` / `ls` / `head` / … that duplicate the uutils safe subset
- Growing `cli-kit` with tools already in `wwn_safe_subset[]`
- Claiming wasm is the primary way to get coreutils on device

Canonical prose: `wasm-packages/README.md`, `docs/wasm-wasi.md`.
