---
name: wawona-ios-min-os
description: Pointer for iOS 11-27 min OS vs latest SDK. One ANGLE, one MoltenVK. Never downgrade iPhoneOS SDK. Open the wawona-ios-min-os rule.
---

# iOS min OS (pointer)

Open rule `wawona-ios-min-os`. Prose:
`Wawona/docs/agent-rules/wawona-ios-min-os.md`.
RAG: `wwn-mcp/knowledge/wawona/ios-min-os.md`.
Tracker: https://github.com/Wawona/Wawona/milestone/4 (meta #178).

## When

Editing `IPHONEOS_DEPLOYMENT_TARGET`, Apple `deploymentTarget`, ANGLE iOS,
MoltenVK iOS, `xcodegen.nix` iOS min, or `@available` / weak-link on iOS.

## Hard rejects (one line)

- Do not pin or downgrade the iPhoneOS SDK to match iOS 11
- Do not ship four ANGLE or four MoltenVK versions
- Do not let a dep recipe pick its own min OS
- Do not replace Nix with a UTM-style CMake product root
- Do not put Metal/Vulkan cap policy in ObjC when Rust can own it
- Do not drop TrollStore / Sileo iOS 11-14 because ASC upload range is 15+
- Do not add extra GLES translation hops on iOS (ANGLE Metal is the path)

Query `wwn-mcp` first (`where_to_edit` ANGLE/MoltenVK → `wwn-iland`;
`IPHONEOS_DEPLOYMENT_TARGET` → `wwn-toolchain`).
