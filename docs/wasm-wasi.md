# Wawona WASM / WASI runtime

Milestone: [Support WASI P1 P2 WASM!](https://github.com/Wawona/Wawona/milestone/2)

Wawona runs **native in-process ports** first (zsh, uutils, weston-terminal, foot, …).
**Wawona Runtime** (`wwn-wasm`) is the long-tail path: compile to WASI, install or
drop a `.wasm`, run it inside the reviewed interpreter. Apple does **not** sign
the module. There is **no** StoreKit/`apt` Mach-O module catalog (`wwn-apt` was
removed).

Wasm packages are **not** OCI Linux containers (`wwn-containers`) and **not**
VMs (`wwn-vms`). Same app process, sandboxed Runtime only.

## Delivery (two ingest paths)

```text
Files.app / SCP / File Sharing     bundled Wasm package client (OCI preferred)
        │                                      │
        └──────────────┬───────────────────────┘
                       ▼
              local package / Documents store
                       ▼
                 Wawona Runtime (WASI P1/P2)
                       ▼
              host WIT (FS, sockets, Wayland, …)
```

| Path | Who |
|---|---|
| Drop `foo.wasm` under Wawona Documents | Developers / power users (rootshell-style) |
| Package client install/search | Everyday users; registry packages as Runtime **data** |

Do not brand this as an “App Store” for iOS apps — it is a **runtime package
registry**. Prefer OCI artifacts + a thin client over inventing a bespoke protocol.

## App Store

| Allowed | Forbidden |
|---|---|
| User `.wasm` as a **document** (Files / File Sharing / `scp`) | Downloading or `exec` of unsigned **Mach-O** |
| Pulley **interpreter** on iOS / iPadOS / tvOS / visionOS | Cranelift native / `MAP_JIT` on Apple mobile |
| Sandbox FS preopen (HOME / Documents) | `..` escape, `dlopen` of `.wasm` |
| POSIX sockets + host Wayland fd-bridge | Shipping WASM as the only way to run a port we already have natively |
| Registry packages as Wasm **data** for the Runtime | Creating a storefront for other iOS apps |

macOS may use Cranelift ([`wawona-macos-no-appstore`](../.cursor/rules/wawona-macos-no-appstore.mdc)).
watchOS keeps the runtime **off** (size), same as coreutils.

iPhone Settings → **Apple Watch** can still **transfer** `.wasm` documents to
the paired Watch via WatchConnectivity (`Documents/Wawona/inbox`). Transfer is
not the same as running them — the Watch interpreter stays unlinked until the
size gate lifts ([#151](https://github.com/Wawona/Wawona/issues/151),
[#156](https://github.com/Wawona/Wawona/issues/156)).

See [ios-local-shell/APP-STORE-COMPLIANCE.md](ios-local-shell/APP-STORE-COMPLIANCE.md).

## Shell

```text
help                 catalog (builtins, uutils, clients, WASM)
ls $WAWONA_ROOTFS/usr/bin
ls ../usr/bin        from HOME
wasm ./tool.wasm hello
./tool.wasm hello    magic \0asm
```

Drop files into the Wawona Documents folder (Files.app / iTunes File Sharing;
`UIFileSharingEnabled` is already on).

## Compile (no Nix)

Use the language toolchain. Do not wrap these in Nix.

```bash
# Rust WASI P1 — https://rustup.rs
rustup target add wasm32-wasip1
cargo build --target wasm32-wasip1 --release

# Rust WASI P2
rustup target add wasm32-wasip2
cargo build --target wasm32-wasip2 --release

# Go 1.21+ — https://go.dev/dl/
GOOS=wasip1 GOARCH=wasm go build -o tool.wasm

# TinyGo (optional)
tinygo build -target=wasip1 -opt=z -o tool.wasm

# Swift 6.2+ wasm SDK — https://swift.org/documentation/articles/wasm-getting-started.html
# (examples/wayland-shm/swift/build.sh installs the wasip1 SDK if missing)
swift build --swift-sdk 6.3-RELEASE-wasm32-unknown-wasip1 -c release

# C (wasi-sdk) / Zig
clang --target=wasm32-wasi -o tool.wasm tool.c
zig build-exe -target wasm32-wasi tool.zig
```

**Wayland client** (same `wl_shm` + xdg rectangle in three languages):

```bash
git clone https://github.com/Wawona/wwn-wasm
cd wwn-wasm/examples/wayland-shm
./rust/build.sh    # or ./go/build.sh or ./swift/build.sh
```

Then `wasm ./wayland-shm-rust.wasm` on device. Native `weston-simple-shm` remains
the supported port.

Other demos: `examples/rust`, `go`, `swift`, `wasip2`.

## Host ABI (P1 extras)

WASI P1 has no sockets. Import module `wawona_socket` (Rust may use `env`):

- `wawona_socket_socket` / `connect_host` / `send` / `recv` / `close`
- `wawona_wayland_connect` / `shm_create` / `shm_write` / `sendmsg`
  (protocol bytes + optional `SCM_RIGHTS` into the existing compositor —
  same `WAYLAND_DISPLAY`, not a custom draw API)

Terminal: `wawona_terminal_set_raw` / `is_tty` (module `wawona_terminal`).

P2 guests use `wasi:cli` / `filesystem` / `sockets` / `clocks` / `random`.
`wasi:http` is not linked yet (size); use `wasi:sockets` or a native port.

## DAG

`wwn-wasm` is L3′: flake input is `wwn-toolchain` only. Wawona merges the
fragment. Cited from [wwn-repo-dag.md](wwn-repo-dag.md).
