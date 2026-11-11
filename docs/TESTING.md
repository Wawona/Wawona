# Darwin CLI tests

## Mode A

Rust:

```bash
cargo test --lib darwin_cli
cargo xtask verify darwin-cli-mode-a
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

The Mode B Darwin tools (launchctl, defaults, ldid, uikittools) are catalog
debs in `repo.wawona.io`, not part of this repository. Install them only on
`vphone wawona-jb`, from the Wawona APT source the lab adds:

```text
packages apt update --device "vphone wawona-jb"
packages apt install launchctl --device "vphone wawona-jb"
```

`cargo xtask package ios-mode-b` builds the Wawona tipa and Sileo debs.

Replay: `.agent-device/wawona-vphone-darwin-cli.ad`.
