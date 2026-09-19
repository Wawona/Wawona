# Wayland protocol conformance (WLCS)

Wawona is tested against Canonical's
[Wayland Conformance Test Suite](https://github.com/MirServer/wlcs) from the
repository's pinned nixpkgs. The adapter drives the production Rust compositor
through the hand-written `WWNCore*` C ABI used by the ObjC and JNI hosts. It
does not use a mock compositor or a separately implemented protocol server.

## Run locally on NixOS/Linux

```sh
nix run .#wawona-wlcs-run
```

Results are written to `wlcs-results/`:

- `wlcs.xml`: upstream GoogleTest XML
- `wlcs.log`: complete runner output
- `summary.json`: stable, machine-readable score and per-test status
- `summary.md`: human-readable verdict and failed-test list

The default policy is deliberately strict: 100% of scored tests must pass and
WLCS itself must exit successfully. A diagnostic run can use a lower threshold,
but such a run is explicitly reported as policy-relaxed:

```sh
nix run .#wawona-wlcs-run -- \
  --minimum-pass-rate 95 --maximum-failures 10 \
  --gtest_filter='*Xdg*'
```

## What the integration exercises

The shared WLCS adapter:

1. creates and starts a real `WWNCore`;
2. runs its Wayland event loop on a dedicated thread;
3. gives WLCS directly registered socketpair client fds;
4. maps WLCS's client-side `wl_surface` ids back to Wawona's client-scoped
   server resources for deterministic window placement; and
5. injects synthetic pointer and touch events through the production input
   path.

It compiles against nixpkgs' WLCS headers and pkg-config metadata. Re-declaring
the ABI locally is forbidden because that can produce an apparently runnable
adapter with an incompatible vtable.

## CI policy

`Gate: Wayland conformance` runs the full battery on x86_64 and aarch64 Linux
for relevant changes, nightly from `development`, and on manual dispatch.
Reports are uploaded even when the strict verdict fails. A green job means the
full advertised WLCS profile passed; skipped tests are reported but do not
inflate the pass rate.

WLCS validates compositor-side Wayland protocol behavior. Running it on Linux
also exercises the same portable Rust core shipped on other targets, but it
does **not** prove SwiftUI/Compose/GTK host integration, graphics-driver
conformance, or Apple/Play store compliance. Those remain separate product and
device gates.
