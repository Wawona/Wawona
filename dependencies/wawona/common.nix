{ lib, pkgs, wawonaSrc, ... }:

rec {
  # Common dependencies
  commonDeps = [
    "waypipe"
    "zstd"
    "lz4"
  ];

  # Source files shared across macOS AND iOS builds.
  # Apple product UI is Swift under Sources/WawonaApple, Sources/WawonaUI,
  # and Darwin/Sources. The @objc class WWNCompositorView_ios lives in
  # Sources/WawonaApple/Present/CompositorView.swift.
  commonSources = [
    # New Skip SwiftPM sources
    "Darwin/Sources/Main.swift"
    "Sources/WawonaModel/ClientLauncher.swift"
    "Sources/WawonaModel/MachineProfile.swift"
    "Sources/WawonaModel/ContainerHubModels.swift"
    "Sources/WawonaModel/SessionOrchestrator.swift"
    "Sources/WawonaModel/WawonaPreferences.swift"
    "Sources/WawonaModel/WWNKeychain.swift"
    "Sources/WawonaUIContracts/MachineEditorContracts.swift"
    "Sources/WawonaUIContracts/SettingsContracts.swift"
    "Sources/WawonaUI/WawonaApp.swift"
    "Sources/WawonaUI/MachineRuntimeSettingsApplicator.swift"
    "Sources/WawonaUI/MachineSessionBridge.swift"
    # Sources/WawonaApple is compiled via xcodegen wawonaAppleSources (full tree).
    "Sources/WawonaUI/CompositorBridge.swift"
    "Sources/WawonaUI/WelcomeView.swift"
    "Sources/WawonaUI/ContentView.swift"
    "Sources/WawonaUI/Components/GlassCard.swift"
    "Sources/WawonaUI/Components/SectionHeader.swift"
    "Sources/WawonaUI/Components/StatusBadge.swift"
    "Sources/WawonaUI/AccessibilityIdentifiers.swift"
    "Sources/WawonaUI/Machines/MachinesRootView.swift"
    "Sources/WawonaUI/Machines/MachinesGridView.swift"
    "Sources/WawonaUI/Machines/MachineCardView.swift"
    "Sources/WawonaUI/Machines/MachineActionBar.swift"
    "Sources/WawonaUI/Machines/MachineEditorView.swift"
    "Sources/WawonaUI/Machines/BundledClientPickerView.swift"
    "Sources/WawonaUI/Machines/MachineFuzzySearch.swift"
    "Sources/WawonaUI/Machines/MachineDetailView.swift"
    "Sources/WawonaUI/Settings/PlatformGlobalSettings.swift"
    "Sources/WawonaUI/Settings/MachineSettingsView.swift"
    "Sources/WawonaUI/View+WawonaTextField.swift"
    "Sources/WawonaUI/VisionOS/WawonaVisionShell.swift"
    # Phone + tvOS Safari-style Wayland client tabs (#84).
    "Sources/WawonaUI/Session/WWNClientSessionTabs.swift"
    # Toolbar drawing is github:Wawona/ToolbarKeys apple/Keyboard.
    # That implementation starts from Rootshell
    # (Copyright (c) 2026 Rootshell LLC, Kit Knox).
    # The Wayland bridge, WWNKeyboardAccessoryView.swift, is compiled
    # with Sources/WawonaUI by xcodegen. Do not list a second toolbar here.
    "Sources/WawonaWatch/WawonaWatchApp.swift"
    "Sources/WawonaWatch/MachineStatusView.swift"
    "Sources/WawonaWatch/QuickConnectView.swift"
    "Sources/WawonaWatch/SessionGlanceView.swift"
    # Platform bridge headers / C stubs (no .m). Swift lives in Sources/WawonaApple.
    "src/platform/macos/WWNSettings.h"
    "src/platform/macos/WWNSettings.c"
    "src/util/wwn_startup_log_sink.c"
    "src/platform/ios/WWNWatchCompanionBridgeConstants.c"
    "src/platform/macos/ui/Machines/wawona_relay.h"
    "src/platform/macos/ui/Machines/wawona_relay_copy_frame_stub.c"
    "src/platform/macos/ui/Settings/WWNSettingsDefines.h"
  ];


  # Helper to filter source files that exist
  filterSources = sources: lib.filter (f: 
    if lib.hasPrefix "/" f then lib.pathExists f
    else lib.pathExists (wawonaSrc + "/" + f)
  ) sources;

  # Compiler flags from CMakeLists.txt
  commonCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Werror"
    "-Wstrict-prototypes"
    "-Wmissing-prototypes"
    "-Wold-style-definition"
    "-Wmissing-declarations"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wwrite-strings"
    "-Wconversion"
    "-Wsign-conversion"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstrict-overflow=5"
    "-Wswitch-default"
    "-Wswitch-enum"
    "-Wunreachable-code"
    "-Wfloat-equal"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fPIC"
    "-D_FORTIFY_SOURCE=2"
    "-DUSE_RUST_CORE=1"
    # Suppress warnings
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-sign-conversion"
    "-Wno-implicit-float-conversion"
    "-Wno-missing-field-initializers"
    "-Wno-format-nonliteral"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-empty-translation-unit"
    "-Wno-format-pedantic"
  ];

  # Apple-only deployment target flag (not valid for Android)
  appleCFlags = [ "-mmacosx-version-min=14.0" ];

  commonObjCFlags = [
    "-Wall"
    "-Wextra"
    "-Wpedantic"
    "-Wuninitialized"
    "-Winit-self"
    "-Wpointer-arith"
    "-Wcast-qual"
    "-Wformat=2"
    "-Wformat-security"
    "-Wundef"
    "-Wshadow"
    "-Wstack-protector"
    "-fstack-protector-strong"
    "-fobjc-arc"
    "-Wno-unused-parameter"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-implicit-float-conversion"
    "-Wno-deprecated-declarations"
    "-Wno-cast-qual"
    "-Wno-format-nonliteral"
    "-Wno-format-pedantic"
  ];

  releaseCFlags = [
    "-O3"
    "-DNDEBUG"
    "-flto"
  ];
  releaseObjCFlags = [
    "-O3"
    "-DNDEBUG"
    "-flto"
  ];

  debugCFlags = [
    "-g"
    "-O0"
    "-fno-omit-frame-pointer"
  ];
}
