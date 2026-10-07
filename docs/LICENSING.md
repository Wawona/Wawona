# Darwin CLI licensing

Mode A command sources in `Sources/WawonaApple/Shell/` Darwin CLI Swift + `src/darwin_cli` are Wawona
code. They call public system frameworks. They are not a copy of Apple's
`plutil`, `defaults`, `sips`, or `sw_vers` binaries, and they are not a
disassembly of those binaries.

| Component | License | In the App Store app? |
|---|---|---|
| Mode A CLI sources | Wawona project license | yes |
| Procursus repository metadata | 0BSD | no |
| ProcursusTeam/defaults | MIT | no (Mode B candidate) |
| ProcursusTeam/launchctl | BSD-2-Clause | no |
| ProcursusTeam/uikittools-ng | BSD-3-Clause and BSD-4-Clause, per file | no |
| ProcursusTeam/ldid | AGPL-3.0 | no. A later Mode B package must ship the AGPL source offer with the package |
| Diatrus/plutil | confirm before any link | no. Mode A uses Foundation |
| Procursus `sw_vers.c` | BSD-3-Clause | no. Private CF symbol |

If a GPL, LGPL, or AGPL package is adopted for Mode B, the Debian package
must include the corresponding source and the license text. That package is
distributed from `repo.wawona.io`, not inside the App Store IPA.

Do not assume every Apple open-source drop uses the APSL. Check the file
header of each port before compiling it.
