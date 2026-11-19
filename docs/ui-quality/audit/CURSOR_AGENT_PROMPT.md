# Cursor agent prompt — Wawona macOS UI remediation

Read `WAWONA_MACOS_UI_AUDIT.md` completely, including the four screenshots in `assets/`, the proposed wireframe, defect register, native UX laws, and acceptance checklist. This is your active engineering specification.

Your objective is to transform the Wawona Compositor macOS interface into a coherent native macOS desktop application targeting the installed macOS 27 SDK/Xcode 27 environment, with correct system-managed Liquid Glass usage where appropriate, robust desktop interactions, and accurate machine/session state.

**Start by inspecting the repository and installed SDK.** Identify AppKit, SwiftUI, Expo/Exact contract generation, Rust and UniFFI boundaries. Do not assume which layer owns the UI; do not edit generated output when the source contract should be edited. Preserve cross-platform semantics and existing working features.

Execute a continuous, bounded engineering loop: baseline build and launch → inspect every reachable screen and state → capture screenshots/accessibility tree → grade using the audit rubric → select highest-severity evidenced defect → implement smallest coherent correction → build → exercise mouse, keyboard and accessibility → capture after screenshots → compare → run regression tests → log evidence in `UI_AUDIT_PROGRESS.md` → repeat.

Fix all P0 issues before visual polish. Never claim planned/unsupported runtimes can start. Distinguish runtime support, readiness, execution and connection. Implement a proper Machines browser, native toolbar/search/filter, compact inspector, native Settings scene and session window semantics. Use actual native system controls/materials; do not hand-draw fake glass.

Apply platform-native UX rules to each platform rather than copying macOS layouts to other targets. Scope this run to macOS unless a shared contract change is essential.

Do not fabricate tests, screenshots, SDK APIs, or passing scores. If a tool, simulator, platform or runtime is unavailable, record it as unverified and proceed with independently testable work. Do not make destructive data changes or ship releases without authorization.

For each iteration report exact changed files, commands, screenshots, failures, resolved defects, outstanding risks and next step. Stop when the release gates pass, or when further progress is blocked; report the blocker clearly. Do not optimize only for a self-assigned visual score.
