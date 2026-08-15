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

@Test
func watchGlobalSettingsMatchShippedCatalog() {
    let sections = GlobalSettingsCatalog.visibleSections(for: .watchOS)
    #expect(sections == [
        .display, .input, .graphics, .connection, .waypipe, .ssh, .advanced, .about,
    ])
    #expect(!sections.contains(.desktop))
    #expect(GlobalSettingsCatalog.visibleFields(in: .display, for: .watchOS) == [.autoScale])
    #expect(!GlobalSettingsCatalog.visibleFields(in: .display, for: .watchOS).contains(.forceSSD))
    let input = GlobalSettingsCatalog.visibleFields(in: .input, for: .watchOS)
    #expect(input.contains(.touchInputType))
    #expect(input.contains(.virtualCursor))
    #expect(input.contains(.nestedCompositorCursor))
    #expect(input.contains(.universalClipboard))
    let connection = GlobalSettingsCatalog.visibleFields(in: .connection, for: .watchOS)
    #expect(connection == [.waylandDisplay, .defaultWaylandClient])
    #expect(GlobalSettingsCatalog.visibleFields(in: .waypipe, for: .watchOS).contains(.waypipeByDefault))
    #expect(GlobalSettingsCatalog.visibleFields(in: .advanced, for: .watchOS).contains(.compositorBackend))
}

@Test
func iosGlobalSettingsIncludeInputAndWaypipe() {
    let sections = GlobalSettingsCatalog.visibleSections(for: .iOS)
    #expect(sections.contains(.input))
    #expect(sections.contains(.waypipe))
    #expect(sections.contains(.appleWatch))
    #expect(!sections.contains(.desktop))
    #expect(GlobalSettingsCatalog.visibleFields(in: .display, for: .iOS).contains(.respectSafeArea))
    let watchFields = GlobalSettingsCatalog.visibleFields(in: .appleWatch, for: .iOS)
    #expect(watchFields == [.watchCompanionStatus, .watchSendDocument, .watchOpenDocumentsHint])
}

@Test
func watchGlobalSettingsOmitAppleWatchCompanionSection() {
    let sections = GlobalSettingsCatalog.visibleSections(for: .watchOS)
    #expect(!sections.contains(.appleWatch))
    #expect(!sections.contains(.localShell))
    #expect(GlobalSettingsCatalog.visibleFields(in: .appleWatch, for: .watchOS).isEmpty)
}

@Test
func visionOSOmitsAppleWatchCompanionSection() {
    let sections = GlobalSettingsCatalog.visibleSections(for: .visionOS)
    #expect(!sections.contains(.appleWatch))
    #expect(sections.contains(.localShell))
}
