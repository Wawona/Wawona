# Wawona Relay runtime map (ALL_TARGETS)

Relay **is** the product runtime for Machines kinds `virtual_machine`,
`container`, and Wasm (`wpm` / Native Shell wasm sessions). Host engines
differ by platform. Do not invent a second runtime beside Relay.

## Engine table

| Target | VM | Container | Wasm execute |
|---|---|---|---|
| **macOS** | **Virtualization.framework** (Relay / `wawona-vz`) | **Apple Containerization** (`wwn-containerd`) | **Wasmtime** Cranelift |
| **Linux** | KVM (cloud-hypervisor / crosvm via Relay) | OCI-in-VM on that KVM guest | Wasmtime Cranelift |
| **iOS / iPadOS ≤ 26 Mode A** | Custom NixOS runner + **AOT** (jitless). Fail closed until green | OCI-in-VM on that runner | **Pulley** (no Cranelift, no `MAP_JIT`) |
| **iOS / iPadOS ≤ 26 Mode B** | Same Mode A path **plus** JIT where tipa/Sileo allows; **crate-ios** ([oneamendez/crate-ios](https://github.com/oneamendez/crate-ios)) | Same + JIT | Pulley **or** crate-ios JIT when armed |
| **iOS / iPadOS 27+ Mode A** | Near-term: AOT runner. Later: custom Linux kernel on **Wasmer SDK** (WASIX, fork) | Same as VM lane | **Wasmer SDK** in hidden WKWebView (WebKit JIT + JSPI) when `WWN_WASMER_IOS27` links WasmerSDK. Else Pulley |
| **Android Play** | Relay jitless (planned) | OCI-in-VM (planned) | Pulley or store-safe Cranelift |
| **Android root / Mode B** | Relay + JIT where artifact allows | Same | Same bytecode; JIT allowed |
| **tvOS / visionOS** | VM/container **forbidden** | **forbidden** | Pulley (visionOS may follow iOS 27 Wasmer gate later) |
| **watchOS / wearOS / asteroidOS** | **forbidden** | **forbidden** | Wasm **required** + remote SSH/waypipe. No GPU wasm on watchOS |

## Jitless Linux-in-Wasm (all Apple mobile floors)

[unkernel](https://github.com/pithings/unkernel) (Linux kernel in WASM) plus a
WASI P1 runtime can host repo.wawona.io packages as **jitless** VM/container
class guests (App Store compliant: no fork in the store P1 engine). Combine
with any Linux userspace that speaks that ABI. This is a Relay lane, not a
second Machines kind.

iOS 27+ Wasmer WASIX (fork + extensions) is the path that retires Mode A AOT
for near-native VM speeds when that kernel work lands.

## Hard rules

1. macOS VM and container gates are **available**, not planned.
2. Watches: Wasm + remote only. Never offer VM/container kinds.
3. Store Mode A never links Cranelift, `MAP_JIT`, crate-ios, or ElleKit.
4. Guest GUI is always Wayland into Wawona (iland). Never UTM Spice/virgl.
5. Wasm packages stay `/wasm/v1` bytecode. Engines above only **execute** them.

Canonical rules: `wawona-relay-wasm`, `wawona-linux-vms-relay-runtime`,
`wawona-mode-a-b`, `wawona-ios-mode-b-channels`, `wawona-platform-targets`.
