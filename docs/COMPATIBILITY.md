# Darwin CLI compatibility

One command syntax. Two products. Scores from Rust tests plus planned device transcripts.

| Score | Meaning |
|---|---|
| PASS | Covered flags match expected exit and stdout in `cargo test --lib darwin_cli` |
| PARTIAL | Documented subset |
| VIRTUAL | Wawona-owned data |
| MODE-A-UNAVAILABLE | Explicit capability, exit 1 |
| MODE-B-ONLY | Debian package, not in the App Store binary |

## Mode A (Rust + Swift)

| Command | Mode A | Notes |
|---|---|---|
| `plutil -lint` | PASS | cargo test |
| `defaults write/read` | PARTIAL | container plists |
| `xattr` | PASS subset | POSIX on Apple |
| `sips` | PARTIAL | Swift ImageIO |
| `sw_vers` | PARTIAL | compile target name |
| `pbcopy` / `pbpaste` / `say` / `open` | PARTIAL | Swift UIKit / AVFoundation |
| `ditto` GetFileInfo SetFile security log system_profiler caffeinate networksetup scutil ioreg | PARTIAL | public or restricted |
| `launchctl` diskutil hdiutil mdfind mdls mdutil lsregister pmset spctl tmutil softwareupdate codesign-inspect | VIRTUAL | Wawona state dir |
| `kmutil` csrutil metal simctl uiopen ldid and the rest of the jailbreak-only names | MODE-A-UNAVAILABLE | cargo test for kmutil/uiopen |

## Mode B

Packages exist under `packaging/mode-b-darwin/out/`. `vphone wawona-jb` was not booted at the last check, so install/remove/upgrade was not run on the guest.
