import Testing
@testable import WawonaUIContracts

@Test
func settingsValidationRejectsEmptyDisplay() {
    let state = ConnectionSettingsState(
        waylandDisplay: "   ",
        sshHost: "",
        sshUser: "",
        sshPortText: "0",
        waypipeCommand: ""
    )
    let issues = ConnectionSettingsValidation.validate(state)
    #expect(issues.contains(.emptyWaylandDisplay))
    #expect(issues.contains(.emptySSHHost))
    #expect(issues.contains(.emptySSHUser))
    #expect(issues.contains(.invalidSSHPort))
    #expect(issues.contains(.emptyWaypipeCommand))
}

@Test
func settingsNormalizationFallsBackToDefaultDisplay() {
    let state = ConnectionSettingsState(waylandDisplay: "  ")
    let normalized = ConnectionSettingsValidation.normalizedDisplay(state)
    #expect(normalized == "wayland-0")
}

@Test
func settingsMetadataMarksDisplayAsRequired() {
    let meta = ConnectionSettingsValidation.metadata(for: .waylandDisplay)
    #expect(meta.required)
    #expect(meta.label == "Wayland Display")
}

@Test
func settingsNormalizationParsesPort() {
    let state = ConnectionSettingsState(
        waylandDisplay: "wayland-2",
        sshHost: "host",
        sshUser: "user",
        sshPortText: "2200",
        waypipeCommand: "weston-terminal"
    )
    #expect(ConnectionSettingsValidation.normalizedSSHPort(state) == 2200)
}
