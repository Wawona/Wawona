# Darwin CLI tests

## Mode A

Rust:

```bash
cargo test --lib darwin_cli
python3 .github/scripts/verify-darwin-cli-mode-a.py
```

Device acceptance is agent-device on the iOS Simulator:

```bash
source scripts/lib/agent-device-ios-system-ui.sh && ios_prepare_system_ui
scripts/agent-device-smoke.sh ios-darwin-cli
```

Replay: `.agent-device/wawona-ios-darwin-cli.ad`. Artifacts:
`.agent-device/test-artifacts/darwin-cli/mode-a/`.

The in-process shell needs a rebuilt `libwwn-pty.a` that maps Darwin names to
`wawona_darwin_cli_main`, and rootfs template 29.

## Mode B

```bash
chmod +x packaging/mode-b-darwin/build-debs.sh
./packaging/mode-b-darwin/build-debs.sh
```

Install only on `vphone wawona-jb`:

```text
packages apt install ./packaging/mode-b-darwin/out/wawona-defaults_26.10.6_iphoneos-arm64.deb
```

Replay: `.agent-device/wawona-vphone-darwin-cli.ad`.
