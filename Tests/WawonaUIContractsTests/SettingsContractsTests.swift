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
        .display, .input, .graphics, .connection, .environment,
        .machines, .iCloudSync, .waypipe, .ssh, .advanced, .about,
        .dependencies,
    ])
    #expect(!sections.contains(.desktop))
    #expect(GlobalSettingsCatalog.visibleFields(in: .display, for: .watchOS) == [.colorOperations])
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
    #expect(sections.contains(.machines))
    #expect(sections.contains(.iCloudSync))
    #expect(sections.contains(.dependencies))
    #expect(!sections.contains(.desktop))
    #expect(GlobalSettingsCatalog.visibleFields(in: .display, for: .iOS).contains(.respectSafeArea))
    #expect(GlobalSettingsCatalog.visibleFields(in: .display, for: .iOS).contains(.colorOperations))
    #expect(!GlobalSettingsCatalog.visibleFields(in: .display, for: .iOS).contains(.forceSSD))
    #expect(GlobalSettingsCatalog.visibleFields(in: .graphics, for: .iOS) == [
        .vulkanDriver, .openGLDriver,
    ])
    #expect(GlobalSettingsCatalog.visibleFields(in: .machines, for: .iOS).contains(.shakeToClose))
    #expect(GlobalSettingsCatalog.visibleFields(in: .machines, for: .iOS).contains(.sessionThumbnails))
    #expect(GlobalSettingsCatalog.visibleFields(in: .machines, for: .iOS).contains(.vmEngine))
    #expect(!GlobalSettingsCatalog.visibleFields(in: .machines, for: .watchOS).contains(.vmEngine))
    #expect(GlobalSettingsCatalog.visibleFields(in: .machines, for: .watchOS).contains(.sessionThumbnails))
    #expect(GlobalSettingsCatalog.visibleFields(in: .advanced, for: .iOS) == [
        .nestedCompositors, .compositorBackend, .multipleClients, .logLevel,
    ])
    let watchFields = GlobalSettingsCatalog.visibleFields(in: .appleWatch, for: .iOS)
    #expect(watchFields == [.watchCompanionStatus, .watchSendDocument, .watchOpenDocumentsHint])
}

@Test
func aboutAlwaysIncludesWawonaIoAndAuthor() {
    for host in GlobalSettingsHost.allCases {
        let fields = GlobalSettingsCatalog.visibleFields(in: .about, for: host)
        #expect(fields.contains(.aboutWebsite))
        #expect(fields.contains(.aboutAuthor))
        #expect(fields.contains(.aboutVersion))
        #expect(fields.contains(.aboutPlatform))
    }
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

@Test
func tvOSOmitsICloudDriveSection() {
    let sections = GlobalSettingsCatalog.visibleSections(for: .tvOS)
    #expect(!sections.contains(.iCloudSync))
    #expect(!sections.contains(.localShell))
    #expect(GlobalSettingsCatalog.visibleFields(in: .iCloudSync, for: .tvOS).isEmpty)
}
