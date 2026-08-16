# Wawona Runtime package manager — implementation plan

Status: **design** (not shipping). Replaces retired `wwn-apt` (StoreKit/ODR Mach-O).
Related: [`wasm-wasi.md`](./wasm-wasi.md), [`vms-containers.md`](./vms-containers.md),
[`mode-a-b.md`](./mode-a-b.md),
[`repo.wawona.io`](https://github.com/Wawona/repo.wawona.io).

## Mode A + Mode B

| | Mode A (store / Play) | Mode B (jailbreak / SIP / root) |
|---|---|---|
| Wasm `wpm` + `/wasm/` | **Yes** — primary optional-software path | Yes (still works) |
| Files.app `.wasm` | Yes | Yes |
| Jailbreak APT / `.deb` | **Never** in app | Yes — Sileo + host tooling |
| Mode B IPA extras | N/A | JIT VMs/containers + unsandboxed shell (separate from Wasm) |

Package manager design is part of the product-wide Mode A/B plan — see
[`mode-a-b.md`](./mode-a-b.md) § Package manager.

## Goal

Give every Wawona target (App Store Apple mobile, Play Android, macOS, Linux) an
**iSH-like package UX** for **WASI P1/P2 Wasm packages** that run inside the
reviewed **Wawona Runtime** (`wwn-wasm`) — not ELF/Mach-O, not Linux containers,
not jailbreak `.deb`.

```text
Developer builds foo.wasm (wasm32-wasip1 / wasip2)
        ↓
Publish to repo.wawona.io  (/wasm/ …)
        ↓
wpm install foo   |   Packages GUI   |   Files.app drop
        ↓
Sandbox package store
        ↓
Wawona Runtime → host WIT → Wayland / shell
```

Analogy: iSH’s `apk` installs Alpine packages into an emulated Linux userspace.
Wawona’s client installs **Wasm components into the Runtime store**; the
“kernel” is already in the signed app.

## Non-goals

| Not this | Where that lives |
|----------|------------------|
| StoreKit / ODR Mach-O modules | Removed (`wwn-apt`) |
| Debian `.deb` for App Store Wawona | Never |
| OCI Linux container images / Docker Hub run | `wwn-containers` + Machines kind `container` |
| Full VMs | `wwn-vms` |
| Jailbreak Desktop / anowaW Mode B tweaks | Still **`.deb` / Sileo** on `repo.wawona.io` (separate channel) |

## Dual-channel `repo.wawona.io` (hard firewall)

One host, **two product channels**. App Store / Play binaries may only speak to
the Wasm channel. Jailbreak tools keep the APT/Sileo channel.

```text
repo.wawona.io
├── /wasm/          ← Mode A: App Store + Play + macOS  (Wasm packages ONLY)
│   ├── index.json / OCI registry API
│   ├── packages/<name>/<ver>/…
│   └── examples/   (e.g. wayland-shm demo)
│
└── /jailbreak/     ← Mode B: Sileo / Procursus flat APT  (.deb tweaks)
    ├── Packages / Release
    ├── Desktop / LockScreen tweaks
    └── anowaW Mode B, etc.
```

### Firewall rules

| Surface | May reference `/wasm/` | May reference `/jailbreak/` or Sileo `.deb` |
|---------|------------------------|-----------------------------------------------|
| App Store / TestFlight IPA + in-app UI | Yes | **Never** |
| Play / store-shaped Android | Yes | **Never** |
| `wawona.io` Mode A docs | Yes | No (or “jailbreak docs live elsewhere”) |
| Website jailbreak / Desktop Mode B pages | Optional | Yes |
| Sileo / jailbroken devices | Optional | Yes |

**Revise** older prose that said “App Store must never touch `repo.wawona.io`.”
That applied when the host was **APT-only**. The host is now **split**: Wasm is
store-safe CDN data; jailbreak APT remains off-limits inside store binaries.

Do **not** put `.deb` and `.wasm` in one index. Do **not** auto-discover the
jailbreak tree from the package client.

## Package format

Prefer **OCI artifacts** (same family as `wwn-oci`) with a thin Wawona layout so
we do not invent a Debian-shaped protocol.

### Artifact contents (logical)

| File | Purpose |
|------|---------|
| `component.wasm` | WASI P1 or P2 / Component Model blob |
| `wawona.toml` | name, version, runtime ABI (`wawona-1`), WASI level, caps |
| `*.wit` (optional) | Host imports / world |
| `README` / license | Attribution |
| digest + signature | Content address + publisher trust |

### `wawona.toml` (sketch)

```toml
name = "wayland-shm-demo"
version = "0.1.0"
runtime = "wawona-1"
wasi = "p1"   # or "p2"
entry = "component.wasm"
summary = "Minimal wl_shm + xdg rectangle"

[capabilities]
wayland = true
filesystem = ["documents"]
network = false

[platforms]
# Empty = all Runtime-capable targets; watchOS excluded until Runtime links
```

### Registry index (Phase 1 can be simple)

`https://repo.wawona.io/wasm/v1/index.json` — package name → versions, digests,
media types. Phase 2: full OCI Distribution API under
`https://repo.wawona.io/wasm/v2/` so ORAS / `wwn-oci` clients work unchanged.

First hosted example: **`wwn-wasm/examples/wayland-shm`** (Rust/Go/Swift builds)
as `wayland-shm-demo` under `/wasm/examples/`.

## Client architecture

```text
                 Wawona.app / Wawona.apk
                          │
         ┌────────────────┼────────────────┐
         │                │                │
   Wawona Runtime    Package client     Files ingest
   (wwn-wasm)        (wpm + GUI)        (Documents)
         │                │                │
         │         HTTPS → /wasm/ only     │
         │                │                │
         └────────┬───────┴────────┬───────┘
                  ▼                ▼
            local package store (sandbox)
```

### CLI (shell — iSH-like UX)

In-process or force-loaded staticlib (Apple mobile: no `fork`/`exec` of a
separate Mach-O installer binary beyond existing dispatch patterns).

```text
wpm search [query]
wpm show <name>
wpm install <name>[@version]
wpm install ./local.wasm          # sideload register
wpm list / list --installed
wpm remove <name>
wpm update / upgrade              # optional Phase 2
```

Default registry: `https://repo.wawona.io/wasm/v1` (overridable in Settings /
machine profile — **still Wasm-only URLs**; reject APT paths).

### GUI

- **Packages** pane (global Settings and/or Machine): search, install, remove.
- Language: “Runtime packages,” never “App Store” / “install apps.”
- Android: same pane in Compose settings.

### Local store layout

```text
~/Library/Application Support/Wawona/wasm-packages/   # Apple
# or Documents/Wawona/packages/  (Files-visible optional mirror)
  installed.json
  blobs/<sha256>/
  links/<name> → current version
```

Android: app-private files dir + optional MediaStore/Documents for user drops.

## Platform matrix

| Target | Runtime | Package client | Default registry |
|--------|---------|----------------|------------------|
| iOS / iPadOS / tvOS / visionOS App Store | Pulley | Yes | `repo.wawona.io/wasm` |
| watchOS | Off (size) until gate lifts | Transfer-only | N/A run |
| Android Play | Yes | Yes | same |
| macOS | Cranelift OK | Yes | same (+ optional extra registries) |
| Linux | Yes | Yes | same |

Jailbreak IPA / sideload builds **may** also enable Sileo for `/jailbreak/` —
that code path must be **compile-time or capability-gated** and absent from
store-shaped binaries (`PlatformCapabilities` + product flavors).

## Compliance (Mode A)

Allowed:

- Download **Wasm bytecode** as documents/data for the reviewed interpreter.
- User Files.app / share-sheet / SCP sideload.
- Capability-gated host WIT (FS roots, Wayland, sockets).

Forbidden in store builds:

- Download / `dlopen` / `posix_spawn` of unsigned **Mach-O** / ELF.
- Linking or listing jailbreak `.deb` / tweak installers.
- Presenting packages as independent iOS/Android **apps** or a competing
  app storefront.
- JIT / Cranelift native on Apple mobile (Pulley only).

Android Play: same Wasm-as-data story; no native code from the registry.

## Relation to containers / OCI

| Use OCI for… | Do not use OCI for… |
|--------------|---------------------|
| Distributing Wasm **artifacts** (optional Phase 2) | Running Linux images as package installs |
| Digests, tags, auth, CAS shared with `wwn-oci` | Replacing Machines kind `container` |

`wpm install nginx` must **never** mean `docker pull nginx`. Different verbs,
different stores, different Machines kinds.

## Repo ownership

| Piece | Repo |
|-------|------|
| Interpreter | `wwn-wasm` |
| Package client CLI + store lib | Prefer **`wwn-wasm`** (or thin `wwn-wpm` L3′ if size forces split) |
| Host WIT / Wayland bridge | `wwn-wasm` + Wawona compositor |
| Registry hosting + CI publish | **`repo.wawona.io`** (`/wasm/` + keep `/jailbreak/` APT) |
| GUI Packages | `Wawona` |
| Dispatch / shell PATH hooks | `wwn-zsh` / `wwn-toolchain` dispatch |
| Docs (Mode A) | `Wawona/docs`, `wawona.io` — no jailbreak in store copy |
| Jailbreak `.deb` packaging | `repo.wawona.io` docs (existing packaging.md) |

DAG: package client stays L3′ → `wwn-toolchain` only; no weston/iland flake edge.

## Phased delivery

### Phase 0 — Foundations (done / in progress)

- Runtime linked; Files drop + `wasm ./file.wasm`.
- `wwn-apt` removed.
- Docs distinguish Runtime vs containers vs VMs.

### Phase 1 — Local package store + sideload register

- `wpm install ./foo.wasm` / `wpm list` / `wpm remove`.
- `installed.json` + blob store.
- Shell `help` lists installed Runtime packages.
- No network required.

### Phase 2 — Official registry on `repo.wawona.io/wasm`

- Publish `index.json` + blobs.
- Host **wayland-shm-demo** (and 1–2 CLI demos).
- `wpm search` / `wpm install <name>` against default registry.
- HTTPS pinning / digest verify.
- Update `repo.wawona.io` README: dual-channel firewall.
- App Store Review Notes: “downloads Wasm modules for in-app WASI runtime.”

### Phase 3 — GUI + Android parity

- Packages UI on Apple + Android.
- Same registry; Play compliance notes.
- Per-machine vs global install policy (default: global Runtime store).

### Phase 4 — OCI Distribution + signatures

- ORAS / OCI artifact media types.
- Optional cosign / minisign.
- Share CAS helpers with `wwn-oci` (pull only; no container run).

### Phase 5 — Richer ecosystem

- WIT worlds for Wayland GUI apps beyond shm demo.
- Capability prompts in UI when a package requests network/Wayland.
- Third-party Wasm registries (user-added; still Wasm-only URL allowlist).
- watchOS Runtime if size gate lifts.

### Parallel track — Jailbreak channel (unchanged intent)

- Keep Procursus/Sileo flat APT under `/jailbreak/` (or existing APT root).
- Continue packaging Desktop / LockScreen / anowaW Mode B as **`.deb`**.
- Never merge into `/wasm/` index.
- Website-only docs for Mode B; zero mention in store IPA.

## Example first packages

| Name | Source | Why |
|------|--------|-----|
| `wayland-shm-demo` | `wwn-wasm/examples/wayland-shm` | Proves GUI path: Wasm → Wayland → compositor |
| `hello-wasi` | tiny P1 CLI | Install/search smoke |
| (later) community ports | external | Long-tail; native ports stay preferred when we have them |

## Success criteria

1. App Store / Play build can `wpm install wayland-shm-demo` from
   `repo.wawona.io/wasm` and show the rectangle client — **no** jailbreak strings
   in binary or UI.
2. Files.app drop still works without the registry.
3. Jailbroken device can still add Sileo source for `.deb` tweaks on the same
   host without the store build learning that URL tree.
4. Android Play build uses the same `/wasm/` client path.
5. `container pull` / Machines containers remain a separate product surface.

## Open decisions (resolve in Phase 1–2)

1. CLI name: `wpm` vs `wawona pkg` vs `wasm-pkg`.
2. Single default registry vs allowlist of extra Wasm registries in Settings.
3. Whether user-visible packages also appear under Files (Documents) or only
   Application Support.
4. Exact OCI media type strings and whether Phase 2 skips OCI for plain HTTPS
   blobs first (recommended: **plain index + blobs first**, OCI in Phase 4).
