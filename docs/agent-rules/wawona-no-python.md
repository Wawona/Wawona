# No Python

Wawona's build, CI, tests and tools are Rust (`cargo xtask`), with shell
only where an OS or ABI needs it (Mode B `run-modeb.sh`, launchd helpers,
the host-PATH wrappers). There is no Python in this repository: no `.py`
file, no Python shebang, no `python`/`pip`/`pytest`/`uvx` command, and no
`setup-python` or `setup-uv` action.

Gate: `cargo xtask verify no-python` (the org-quality workflow runs it). It
scans every tracked file under `.github/`, `fastlane/`, `scripts/`, and every
`*.nix`, `*.sh`, `*.rs`, `*.kts`, Xcode project and `.ad` replay. Comments
and prose may name Python; so may a system package a third-party driver pulls
in (`python3-pyatspi` for the Linux Appium driver).

## Do

- A new verifier, generator or lab drive is a `cargo xtask` subcommand.
- A one-off edit uses the editor or `perl -pi`, never an inline Python script.
- A tool published on PyPI but written in another language installs from its
  release binary, pinned by SHA-256 (zizmor in `org-quality.yml`).

## Hard rejects

- Reintroducing a `.py` file, `requirements.txt` or `pyproject.toml`
- `python3 -c` inside a workflow, recipe or script
- Running a Rust or Go tool through `uvx` / `pipx`

Upstream ports keep their language (`wawona-rust-first`). An upstream
recipe that needs `python3` at build time belongs in its `wwn-*` repository
or the `repo.wawona.io` catalog, not in Wawona's Nix files. Sibling
repositories (`wwn-vphone`'s socket tool) are outside this gate.

Cursor: `wawona-no-python`. Related: `wawona-fresh-build`, `wawona-rust-first`.
