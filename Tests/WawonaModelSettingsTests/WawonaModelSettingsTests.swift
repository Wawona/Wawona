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
    preferences.defaultInputProfile = "global-input"
    preferences.defaultWaypipeEnabled = true

    let machine = MachineProfile(
        name: "Machine A",
        type: .sshWaypipe,
        sshHost: "machine.example",
        sshUser: "machine-user",
        sshPort: 2022,
        runtimeOverrides: MachineRuntimeOverrides(
            renderer: "vulkan",
            inputProfile: "machine-input",
            waypipeEnabled: false
        )
    )

    let resolved = preferences.resolvedSettings(for: machine)
    #expect(resolved.renderer == "vulkan")
    #expect(resolved.sshHost == "machine.example")
    #expect(resolved.sshUser == "machine-user")
    #expect(resolved.sshPort == 2022)
    #expect(resolved.inputProfile == "machine-input")
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
    preferences.defaultInputProfile = "direct"
    preferences.defaultWaypipeEnabled = true

    let machine = MachineProfile(name: "Machine B", type: .sshTerminal, sshHost: "", sshUser: "", sshPort: 0)
    let resolved = preferences.resolvedSettings(for: machine)
    #expect(resolved.renderer == "metal")
    #expect(resolved.sshHost == "global.example")
    #expect(resolved.sshUser == "global-user")
    #expect(resolved.sshPort == 2200)
    #expect(resolved.inputProfile == "direct")
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
