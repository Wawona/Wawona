import Testing
@testable import WawonaModel

@MainActor
@Test
func machineOverridesGlobalSettings() {
    let preferences = WawonaPreferences()
    preferences.renderer = "metal"
    preferences.sshHost = "global.example"
    preferences.sshUser = "global-user"
    preferences.sshPort = 2222
    preferences.defaultInputProfile = "Touchpad"
    preferences.defaultWaypipeEnabled = true

    let machine = MachineProfile(
        name: "Machine A",
        type: .sshWaypipe,
        sshHost: "machine.example",
        sshUser: "machine-user",
        sshPort: 2022,
        runtimeOverrides: MachineRuntimeOverrides(
            renderer: "vulkan",
            inputProfile: "Multi-Touch",
            waypipeEnabled: false
        )
    )

    let resolved = preferences.resolvedSettings(for: machine)
    #expect(resolved.renderer == "vulkan")
    #expect(resolved.sshHost == "machine.example")
    #expect(resolved.sshUser == "machine-user")
    #expect(resolved.sshPort == 2022)
    #expect(resolved.inputProfile == "Multi-Touch")
    #expect(resolved.waypipeEnabled == false)
}

@MainActor
@Test
func globalFallbackUsedWhenMachineValuesUnset() {
    let preferences = WawonaPreferences()
    preferences.renderer = "metal"
    preferences.sshHost = "global.example"
    preferences.sshUser = "global-user"
    preferences.sshPort = 2200
    // Legacy "direct" normalizes to Multi-Touch; empty machine override uses global.
    preferences.defaultInputProfile = "direct"
    preferences.defaultWaypipeEnabled = true

    let machine = MachineProfile(name: "Machine B", type: .sshTerminal, sshHost: "", sshUser: "", sshPort: 0)
    let resolved = preferences.resolvedSettings(for: machine)
    #expect(resolved.renderer == "metal")
    #expect(resolved.sshHost == "global.example")
    #expect(resolved.sshUser == "global-user")
    #expect(resolved.sshPort == 2200)
    #expect(resolved.inputProfile == "Multi-Touch")
    #expect(resolved.waypipeEnabled == true)
}

@MainActor
@Test
func diagnosticsAreRecordedForTests() {
    let preferences = WawonaPreferences()
    let sshResult = preferences.testSSHConnection(
        host: "",
        user: "",
        password: "",
        port: 22,
        runtimeProbe: false
    )
    #expect(sshResult.success == false)
    #expect(sshResult.mode == .configLint)
    let depResult = preferences.runDependencyDiagnostics(runtimeProbe: false)
    #expect(depResult.category == .dependency)
    #expect(depResult.mode == .configLint)
    #expect(!preferences.diagnostics.isEmpty)
}

@MainActor
@Test
func runtimeDiagnosticsAreTypedAndPersisted() {
    let preferences = WawonaPreferences()
    let entry = preferences.testWaypipeCommand("weston-terminal", runtimeProbe: true)
    #expect(entry.mode == .runtimeProbe)
    #expect(entry.details["runtimeProbe"] == "true")
    #expect(preferences.diagnostics.first?.id == entry.id)
}

@Test
func environmentMergeMachineBeatsGlobal() {
    let global: EnvironmentOverrideMap = [
        "TERM": .set("vt100"),
        "RUST_LOG": .set("warn"),
    ]
    let machine: EnvironmentOverrideMap = [
        "TERM": .set("xterm"),
    ]
    let rows = EnvironmentResolver.resolve(
        globalOverrides: global,
        machineOverrides: machine,
        session: EnvironmentSessionContext(waylandDisplay: "wayland-0", rustLog: "info")
    )
    let term = rows.first { $0.name == "TERM" }
    #expect(term?.value == "xterm")
    #expect(term?.source == .machineOverride)
    let rust = rows.first { $0.name == "RUST_LOG" }
    #expect(rust?.value == "warn")
    #expect(rust?.source == .globalOverride)
}

@Test
func environmentResetManagedKeepsUserExtras() {
    var map: EnvironmentOverrideMap = [
        "TERM": .set("dumb"),
        "MY_CUSTOM": .set("1"),
    ]
    EnvironmentResolver.resetWawonaManaged(&map)
    #expect(map["TERM"] == nil)
    #expect(map["MY_CUSTOM"]?.value == "1")
}

@Test
func environmentUnsetAndSecretsFiltered() {
    let rows = EnvironmentResolver.resolve(
        globalOverrides: ["RUST_BACKTRACE": .unset],
        machineOverrides: [:],
        session: EnvironmentSessionContext(),
        includeSecrets: false
    )
    let backtrace = rows.first { $0.name == "RUST_BACKTRACE" }
    #expect(backtrace?.isUnset == true)
    let secret = rows.first { $0.name == "SSHPASS" }
    #expect(secret?.isSecret == true)
    #expect(secret?.displayValue.contains("SSH") == true)
    let apply = EnvironmentResolver.applyMap(from: rows)
    #expect(apply["RUST_BACKTRACE"] == nil)
    #expect(apply["SSHPASS"] == nil)
}

@Test
func environmentBannedLocalShellKeysStripped() {
    let rows = EnvironmentResolver.resolve(
        globalOverrides: [
            "DYLD_INSERT_LIBRARIES": .set("/tmp/evil.dylib"),
            "TERM": .set("xterm"),
        ],
        machineOverrides: [:],
        session: EnvironmentSessionContext(),
        stripBannedLocalShellKeys: true
    )
    #expect(rows.contains { $0.name == "TERM" })
    #expect(!rows.contains { $0.name == "DYLD_INSERT_LIBRARIES" })
}

@Test
func environmentNiriBackendAndRustLogMapping() {
    #expect(EnvironmentResolver.niriBackend(for: "drm") == "tty")
    #expect(EnvironmentResolver.niriBackend(for: "wayland") == "nested")
    #expect(EnvironmentResolver.rustLog(for: "debug") == "debug")
    #expect(EnvironmentResolver.rustLog(for: "info") == "info")
}

@MainActor
@Test
func environmentPersistsOnPreferences() {
    let preferences = WawonaPreferences()
    preferences.environmentOverrides = [:]
    preferences.setEnvironmentOverride(name: "TERM", override: .set("screen"))
    #expect(preferences.environmentOverrides["TERM"]?.value == "screen")
    let rows = preferences.resolvedEnvironment(for: nil)
    let term = rows.first { $0.name == "TERM" }
    #expect(term?.value == "screen")
    #expect(term?.source == .globalOverride)
    preferences.resetEnvironmentAll()
    #expect(preferences.environmentOverrides.isEmpty)
}

@MainActor
@Test
func compositorBackendMachineOverride() {
    let preferences = WawonaPreferences()
    preferences.compositorBackend = "auto"
    let machine = MachineProfile(
        name: "DRM",
        runtimeOverrides: MachineRuntimeOverrides(compositorBackend: "drm")
    )
    let resolved = preferences.resolvedSettings(for: machine)
    #expect(resolved.compositorBackend == "drm")
}

@Test
func nestedCompositorDrawsOwnCursorForWestonAndNiri() {
    let weston = MachineProfile(
        name: "Weston",
        type: .native,
        runtimeOverrides: MachineRuntimeOverrides(bundledAppID: "weston")
    )
    let niri = MachineProfile(
        name: "Niri",
        type: .native,
        runtimeOverrides: MachineRuntimeOverrides(bundledAppID: "niri")
    )
    let terminal = MachineProfile(
        name: "Term",
        type: .native,
        runtimeOverrides: MachineRuntimeOverrides(bundledAppID: "weston-terminal")
    )
    #expect(weston.nestedCompositorDrawsOwnCursor)
    #expect(niri.nestedCompositorDrawsOwnCursor)
    #expect(!terminal.nestedCompositorDrawsOwnCursor)
    #expect(weston.isNestedCompositorClient)
    #expect(!niri.isNestedCompositorClient)
}

@Test
func watchPresentAcceleratorIsWatchOnlyAndGpuStackStaysBlocked() {
    #if os(watchOS)
    #expect(PlatformCapabilities.gpuStackGate.isBlocked)
    #expect(PlatformCapabilities.watchPresentAcceleratorGate.isAvailable)
    #expect(PlatformCapabilities.allowsWatchPresentAccelerator)
    #else
    #expect(!PlatformCapabilities.watchPresentAcceleratorGate.isAvailable)
    switch PlatformCapabilities.watchPresentAcceleratorGate {
    case .forbidden(reason: _):
        break
    default:
        Issue.record("watchPresentAcceleratorGate must be forbidden off watchOS")
    }
    #endif
}

@Test
func sshWaypipeSettingsAreRemoteTypesOnly() {
    #expect(!MachineType.native.isSSH)
    #expect(!MachineType.virtualMachine.isSSH)
    #expect(!MachineType.container.isSSH)
    #expect(MachineType.sshWaypipe.isSSH)
    #expect(MachineType.sshTerminal.isSSH)
}
