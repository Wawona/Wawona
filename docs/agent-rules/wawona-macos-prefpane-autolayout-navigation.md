# macOS PrefPane (retired)

Updated 2026-10-09. System Settings → Wawona PrefPane is **retired**.

Global Settings exclusivity (`wawona-global-settings-exclusive`): the sole host
is the **in-app** Machines sidebar catalog. Do not rebuild `Wawona.prefPane`,
`Settings.bundle`, or a PrefPane suite.

Install / pkg / `nix run .#install` **delete** any leftover
`~/Library/PreferencePanes/Wawona.prefPane` and
`/Library/PreferencePanes/Wawona.prefPane`.

Historical notes (Autolayout width, in-pane Back, Env Vars suite) applied only
while the PrefPane shipped. See git history around `8f2335a` if needed. Current
Env Vars editor is in-app (`EnvironmentVariablesView`).
