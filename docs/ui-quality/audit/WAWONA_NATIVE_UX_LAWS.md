# Wawona Native UX Laws — proposed addition to laws.md

1. **Platform authenticity.** Every target MUST follow its host operating system's native navigation, presentation, typography, accessibility, interaction and windowing conventions. Shared contracts define semantics, not identical layouts.
2. **Native controls first.** Prefer system controls, menus, toolbars, materials and accessibility infrastructure. Justify custom controls with a functional requirement.
3. **Information architecture first.** Separate primary navigation, contextual actions, configuration and active sessions. Do not place persistent commands inside an empty state.
4. **Truthful states.** Planned, unsupported, unavailable, stopped, starting, running, stopping and failed MUST not be conflated. UI actions MUST reflect real runtime capability.
5. **Desktop completeness.** On macOS, implement applicable keyboard, contextual menu, focus, selection, window-management and accessibility behavior. Pointer-only is insufficient.
6. **Native system materials.** Use supported system-managed Liquid Glass/material APIs where appropriate. Do not imitate native effects with custom blurs or gradients. Honor reduced transparency/motion and contrast.
7. **Adaptive layout.** Layouts MUST respond to window size, localization and accessibility. Avoid arbitrary absolute positioning where native constraints work.
8. **Verified interaction.** Every visible control MUST have meaningful behavior and applicable loading, success, failure and recovery states. Never imply unsupported functionality.
9. **Continuous evaluation.** On each target: build, launch, navigate every reachable screen/state, capture screenshots, inspect accessibility, compare native conventions, fix defects and retest.
10. **Release gates.** No unresolved P0 defects, misleading enabled actions, inaccessible primary workflows, broken core keyboard/focus paths, critical clipping or major native-navigation violations. Numeric scores never override gates.
11. **Semantic cross-platform consistency.** Rust and shared contracts maintain consistent machine/session semantics; native adapters choose platform-appropriate UI patterns.
12. **Evidence-based improvement.** Agents may iteratively improve UI using screenshots, accessibility trees and computer-use tests, but MUST preserve functionality, record decisions, verify regressions, and require authorization for irreversible data changes or releases. Self-grading alone does not establish completion.
