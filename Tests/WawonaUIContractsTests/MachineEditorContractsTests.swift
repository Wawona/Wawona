import Testing
@testable import WawonaUIContracts

@Test
func nativeVisibilityIncludesLauncherOnly() {
    let state = MachineEditorState(name: "Local", typeRawValue: "native")
    let fields = MachineEditorValidation.visibleFields(for: state)
    #expect(fields.contains(.name))
    #expect(fields.contains(.type))
    #expect(fields.contains(.launcher))
    #expect(!fields.contains(.sshHost))
    #expect(!fields.contains(.remoteCommand))
}

@Test
func sshVisibilityIncludesRemoteFields() {
    let state = MachineEditorState(name: "Remote", typeRawValue: "ssh_waypipe")
    let fields = MachineEditorValidation.visibleFields(for: state)
    #expect(fields.contains(.sshHost))
    #expect(fields.contains(.sshUser))
    #expect(fields.contains(.sshPort))
    #expect(fields.contains(.remoteCommand))
    #expect(!fields.contains(.launcher))
}

@Test
func validationFlagsMissingAndInvalidFields() {
    let state = MachineEditorState(
        name: "",
        typeRawValue: "ssh_terminal",
        sshHost: "",
        sshUser: "",
        sshPortText: "0"
    )
    let issues = MachineEditorValidation.validate(state)
    #expect(issues.contains(.missingName))
    #expect(issues.contains(.missingSSHHost))
    #expect(issues.contains(.missingSSHUser))
    #expect(issues.contains(.invalidSSHPort))
}

@Test
func vmAndContainerVisibility() {
    let vmState = MachineEditorState(name: "VM", typeRawValue: "virtual_machine")
    let vmFields = MachineEditorValidation.visibleFields(for: vmState)
    #expect(vmFields.contains(.vmSubtype))
    #expect(!vmFields.contains(.containerSubtype))

    let containerState = MachineEditorState(name: "Container", typeRawValue: "container")
    let containerFields = MachineEditorValidation.visibleFields(for: containerState)
    #expect(containerFields.contains(.containerSubtype))
    #expect(!containerFields.contains(.vmSubtype))
}

@Test
func vmAndContainerValidation() {
    let vmState = MachineEditorState(name: "VM", typeRawValue: "virtual_machine", vmSubtype: "")
    let vmIssues = MachineEditorValidation.validate(vmState)
    #expect(vmIssues.contains(.missingVMSubtype))

    let containerState = MachineEditorState(name: "Container", typeRawValue: "container", containerSubtype: "")
    let containerIssues = MachineEditorValidation.validate(containerState)
    #expect(containerIssues.contains(.missingContainerSubtype))
}
