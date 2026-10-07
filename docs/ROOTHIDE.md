# Roothide path layout

Jailbreak roots are not interchangeable.

| Variant | Typical layout | Path rule |
|---|---|---|
| Rootful | tools under `/` | `/usr` is the bootstrap, still not a promise about Apple's sealed root |
| Rootless | tools under a prefix such as `/var/jb` | do not hard-code that prefix in commands |
| RootHide | `jbroot()` translates bootstrap paths | `/` in a package script is not Apple's `/` |
| Unknown | detection failed | refuse privileged path rewrites |

Mode A never consults this table. The App Store app uses its container.

Mode B commands, when they exist, must take paths through one
`JailbreakEnvironment` value (`Rootful`, `Rootless`, `RootHide`, `Unknown`).
Do not scatter `/var/jb` or `jbroot` checks through command bodies.

This repository does not yet vendor `roothide/Procursus-roothide` or
`roothide/Bootstrap`. Until that inventory is recorded per package, do not
claim a command is roothide-safe.
