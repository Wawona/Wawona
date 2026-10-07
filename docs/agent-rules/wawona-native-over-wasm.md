# Native over WASI / WASIX (no duplicate packaging)

If a CLI already ships as a **native** port on **every** Wawona product
target, do **not** also package it for WASI / WASIX / `/wasm/v1`.

List: `wasm-packages/scripts/native-all-targets.txt` (mirrors
`wwn_safe_subset[]` in `wawona-dispatch.c`). Cursor rule:
`wawona-native-over-wasm`.
