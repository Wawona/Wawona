# ALL_TARGETS status vs concept pack (2026-11-18)

Concepts live in this directory. Status uses `platforms.json` product/exact_ui
plus whether a running Exact / product grade exists (`target-matrix.json`).

FigCraft editable recreation (2026-11-18): `figcraft/Wawona-ALL_TARGETS.figcraft`
(Machines frames for every ALL_TARGETS id + Android XR extra). Not Exact grade.

| id | Concept PNG | Product | Exact UI | Graded | Notes vs concept |
|---|---|---|---|---|---|
| macos | macOS.png | available | available | yes (~90 tip) | NSToolbar New/Settings/Sessions; Settings cover; no root Images/Runtimes. VO rotor open |
| ios | iOS.png | available | available | no | Compact inset-grouped; Settings gear cover (not bottom Settings tab) |
| ipados | iPadOS.png | available | available | no | Wide split + multi-window sessions required |
| android | Android_Tablet.png | available | available | no | Material 3 Expressive on Android 16+ only |
| linux | Linux.png | planned | available | no | GTK / nested host |
| web | Web_DOM.png | planned | available | no | Exact web host |
| windows | Windows.png | planned | available | no | Fluent |
| visionos | visionOS.png | available | planned | no | Multi-window parity with macOS class |
| tvos | tvOS_Apple_TV.png | available | planned | no | Focus platter; Settings not a peer root of Machines forever (gear cover) |
| watchos | Apple_Watch.png | available | planned | no | Dense lists; no Metal GLES present |
| wearos | Wear_OS.png | planned | available | no | Wear density |
| asteroidos | AsteroidOS_Oppo_Watch.png | planned | available | no | Asteroid chrome |
| *(extra)* | Android_XR.png | n/a | n/a | n/a | Not in ALL_TARGETS yet |

Legend: Graded = recorded Exact agent / computer-use evidence for that host.
Concept alone never marks Graded.
