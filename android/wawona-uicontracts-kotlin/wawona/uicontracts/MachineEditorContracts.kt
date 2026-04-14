package wawona.uicontracts

import skip.lib.*
import skip.lib.Array

import skip.foundation.*

sealed class MachineEditorIntent {
    class UpdateNameCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateTypeCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateLauncherCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateSSHHostCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateSSHUserCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateSSHPortCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateSSHPasswordCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateRemoteCommandCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateVMSubtypeCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateContainerSubtypeCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateInputProfileCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateBundledAppIDCase(val associated0: String): MachineEditorIntent() {
    }
    class UpdateUseBundledAppCase(val associated0: Boolean): MachineEditorIntent() {
    }
    class UpdateWaypipeEnabledCase(val associated0: Boolean): MachineEditorIntent() {
    }

    @androidx.annotation.Keep
    companion object {
        fun updateName(associated0: String): MachineEditorIntent = UpdateNameCase(associated0)
        fun updateType(associated0: String): MachineEditorIntent = UpdateTypeCase(associated0)
        fun updateLauncher(associated0: String): MachineEditorIntent = UpdateLauncherCase(associated0)
        fun updateSSHHost(associated0: String): MachineEditorIntent = UpdateSSHHostCase(associated0)
        fun updateSSHUser(associated0: String): MachineEditorIntent = UpdateSSHUserCase(associated0)
        fun updateSSHPort(associated0: String): MachineEditorIntent = UpdateSSHPortCase(associated0)
        fun updateSSHPassword(associated0: String): MachineEditorIntent = UpdateSSHPasswordCase(associated0)
        fun updateRemoteCommand(associated0: String): MachineEditorIntent = UpdateRemoteCommandCase(associated0)
        fun updateVMSubtype(associated0: String): MachineEditorIntent = UpdateVMSubtypeCase(associated0)
        fun updateContainerSubtype(associated0: String): MachineEditorIntent = UpdateContainerSubtypeCase(associated0)
        fun updateInputProfile(associated0: String): MachineEditorIntent = UpdateInputProfileCase(associated0)
        fun updateBundledAppID(associated0: String): MachineEditorIntent = UpdateBundledAppIDCase(associated0)
        fun updateUseBundledApp(associated0: Boolean): MachineEditorIntent = UpdateUseBundledAppCase(associated0)
        fun updateWaypipeEnabled(associated0: Boolean): MachineEditorIntent = UpdateWaypipeEnabledCase(associated0)
    }
}

@androidx.annotation.Keep
enum class MachineEditorFieldID(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CaseIterable, RawRepresentable<String> {
    name_("name"),
    type("type"),
    launcher("launcher"),
    sshHost("sshHost"),
    sshUser("sshUser"),
    sshPort("sshPort"),
    sshPassword("sshPassword"),
    remoteCommand("remoteCommand"),
    vmSubtype("vmSubtype"),
    containerSubtype("containerSubtype"),
    inputProfile("inputProfile"),
    bundledAppID("bundledAppID"),
    useBundledApp("useBundledApp"),
    waypipeEnabled("waypipeEnabled");

    @androidx.annotation.Keep
    companion object: CaseIterableCompanion<MachineEditorFieldID> {
        fun init(rawValue: String): MachineEditorFieldID? {
            return when (rawValue) {
                "name" -> MachineEditorFieldID.name_
                "type" -> MachineEditorFieldID.type
                "launcher" -> MachineEditorFieldID.launcher
                "sshHost" -> MachineEditorFieldID.sshHost
                "sshUser" -> MachineEditorFieldID.sshUser
                "sshPort" -> MachineEditorFieldID.sshPort
                "sshPassword" -> MachineEditorFieldID.sshPassword
                "remoteCommand" -> MachineEditorFieldID.remoteCommand
                "vmSubtype" -> MachineEditorFieldID.vmSubtype
                "containerSubtype" -> MachineEditorFieldID.containerSubtype
                "inputProfile" -> MachineEditorFieldID.inputProfile
                "bundledAppID" -> MachineEditorFieldID.bundledAppID
                "useBundledApp" -> MachineEditorFieldID.useBundledApp
                "waypipeEnabled" -> MachineEditorFieldID.waypipeEnabled
                else -> null
            }
        }

        override val allCases: Array<MachineEditorFieldID>
            get() = arrayOf(name_, type, launcher, sshHost, sshUser, sshPort, sshPassword, remoteCommand, vmSubtype, containerSubtype, inputProfile, bundledAppID, useBundledApp, waypipeEnabled)
    }
}

fun MachineEditorFieldID(rawValue: String): MachineEditorFieldID? = MachineEditorFieldID.init(rawValue = rawValue)

@Suppress("MUST_BE_INITIALIZED")
class MachineEditorFieldMetadata: MutableStruct {
    var id: MachineEditorFieldID
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var label: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var helperText: String? = null
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var required: Boolean
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }

    constructor(id: MachineEditorFieldID, label: String, helperText: String? = null, required: Boolean = false) {
        this.id = id
        this.label = label
        this.helperText = helperText
        this.required = required
    }

    private constructor(copy: MutableStruct) {
        @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as MachineEditorFieldMetadata
        this.id = copy.id
        this.label = copy.label
        this.helperText = copy.helperText
        this.required = copy.required
    }

    override var supdate: ((Any) -> Unit)? = null
    override var smutatingcount = 0
    override fun scopy(): MutableStruct = MachineEditorFieldMetadata(this as MutableStruct)

    override fun equals(other: Any?): Boolean {
        if (other !is MachineEditorFieldMetadata) return false
        return id == other.id && label == other.label && helperText == other.helperText && required == other.required
    }

    override fun hashCode(): Int {
        var result = 1
        result = Hasher.combine(result, id)
        result = Hasher.combine(result, label)
        result = Hasher.combine(result, helperText)
        result = Hasher.combine(result, required)
        return result
    }

    @androidx.annotation.Keep
    companion object {
    }
}

@Suppress("MUST_BE_INITIALIZED")
class MachineEditorState: MutableStruct {
    var id: String? = null
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var name: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var typeRawValue: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var selectedLauncherName: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var sshHost: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var sshUser: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var sshPortText: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var sshPassword: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var remoteCommand: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var vmSubtype: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var containerSubtype: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var inputProfile: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var bundledAppID: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var useBundledApp: Boolean
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var waypipeEnabled: Boolean
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }

    constructor(id: String? = null, name: String = "", typeRawValue: String = "native", selectedLauncherName: String = "weston-simple-shm", sshHost: String = "", sshUser: String = "", sshPortText: String = "22", sshPassword: String = "", remoteCommand: String = "", vmSubtype: String = "", containerSubtype: String = "", inputProfile: String = "direct", bundledAppID: String = "", useBundledApp: Boolean = false, waypipeEnabled: Boolean = true) {
        this.id = id
        this.name = name
        this.typeRawValue = typeRawValue
        this.selectedLauncherName = selectedLauncherName
        this.sshHost = sshHost
        this.sshUser = sshUser
        this.sshPortText = sshPortText
        this.sshPassword = sshPassword
        this.remoteCommand = remoteCommand
        this.vmSubtype = vmSubtype
        this.containerSubtype = containerSubtype
        this.inputProfile = inputProfile
        this.bundledAppID = bundledAppID
        this.useBundledApp = useBundledApp
        this.waypipeEnabled = waypipeEnabled
    }

    val isNative: Boolean
        get() = typeRawValue == "native"
    val isSSH: Boolean
        get() = typeRawValue == "ssh_waypipe" || typeRawValue == "ssh_terminal"
    val isVirtualMachine: Boolean
        get() = typeRawValue == "virtual_machine"
    val isContainer: Boolean
        get() = typeRawValue == "container"

    private constructor(copy: MutableStruct) {
        @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as MachineEditorState
        this.id = copy.id
        this.name = copy.name
        this.typeRawValue = copy.typeRawValue
        this.selectedLauncherName = copy.selectedLauncherName
        this.sshHost = copy.sshHost
        this.sshUser = copy.sshUser
        this.sshPortText = copy.sshPortText
        this.sshPassword = copy.sshPassword
        this.remoteCommand = copy.remoteCommand
        this.vmSubtype = copy.vmSubtype
        this.containerSubtype = copy.containerSubtype
        this.inputProfile = copy.inputProfile
        this.bundledAppID = copy.bundledAppID
        this.useBundledApp = copy.useBundledApp
        this.waypipeEnabled = copy.waypipeEnabled
    }

    override var supdate: ((Any) -> Unit)? = null
    override var smutatingcount = 0
    override fun scopy(): MutableStruct = MachineEditorState(this as MutableStruct)

    override fun equals(other: Any?): Boolean {
        if (other !is MachineEditorState) return false
        return id == other.id && name == other.name && typeRawValue == other.typeRawValue && selectedLauncherName == other.selectedLauncherName && sshHost == other.sshHost && sshUser == other.sshUser && sshPortText == other.sshPortText && sshPassword == other.sshPassword && remoteCommand == other.remoteCommand && vmSubtype == other.vmSubtype && containerSubtype == other.containerSubtype && inputProfile == other.inputProfile && bundledAppID == other.bundledAppID && useBundledApp == other.useBundledApp && waypipeEnabled == other.waypipeEnabled
    }

    override fun hashCode(): Int {
        var result = 1
        result = Hasher.combine(result, id)
        result = Hasher.combine(result, name)
        result = Hasher.combine(result, typeRawValue)
        result = Hasher.combine(result, selectedLauncherName)
        result = Hasher.combine(result, sshHost)
        result = Hasher.combine(result, sshUser)
        result = Hasher.combine(result, sshPortText)
        result = Hasher.combine(result, sshPassword)
        result = Hasher.combine(result, remoteCommand)
        result = Hasher.combine(result, vmSubtype)
        result = Hasher.combine(result, containerSubtype)
        result = Hasher.combine(result, inputProfile)
        result = Hasher.combine(result, bundledAppID)
        result = Hasher.combine(result, useBundledApp)
        result = Hasher.combine(result, waypipeEnabled)
        return result
    }

    @androidx.annotation.Keep
    companion object {
    }
}

enum class MachineEditorValidationIssue(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<String> {
    missingName("missingName"),
    missingSSHHost("missingSSHHost"),
    missingSSHUser("missingSSHUser"),
    invalidSSHPort("invalidSSHPort"),
    missingVMSubtype("missingVMSubtype"),
    missingContainerSubtype("missingContainerSubtype");

    @androidx.annotation.Keep
    companion object {
        fun init(rawValue: String): MachineEditorValidationIssue? {
            return when (rawValue) {
                "missingName" -> MachineEditorValidationIssue.missingName
                "missingSSHHost" -> MachineEditorValidationIssue.missingSSHHost
                "missingSSHUser" -> MachineEditorValidationIssue.missingSSHUser
                "invalidSSHPort" -> MachineEditorValidationIssue.invalidSSHPort
                "missingVMSubtype" -> MachineEditorValidationIssue.missingVMSubtype
                "missingContainerSubtype" -> MachineEditorValidationIssue.missingContainerSubtype
                else -> null
            }
        }
    }
}

fun MachineEditorValidationIssue(rawValue: String): MachineEditorValidationIssue? = MachineEditorValidationIssue.init(rawValue = rawValue)

/// Declared as `struct` so Skip emits a normal Kotlin class (case-less Swift `enum` becomes an empty Kotlin `enum` and can fail to load on Android).
class MachineEditorValidation {

    @androidx.annotation.Keep
    companion object {
        fun visibleFields(for_: MachineEditorState): Array<MachineEditorFieldID> {
            val state = for_
            var fields: Array<MachineEditorFieldID> = arrayOf(MachineEditorFieldID.name_, MachineEditorFieldID.type)
            if (state.isNative) {
                fields.append(MachineEditorFieldID.launcher)
                fields.append(MachineEditorFieldID.useBundledApp)
                if (state.useBundledApp) {
                    fields.append(MachineEditorFieldID.bundledAppID)
                }
            } else if (state.isSSH) {
                fields.append(contentsOf = arrayOf(
                    MachineEditorFieldID.sshHost,
                    MachineEditorFieldID.sshUser,
                    MachineEditorFieldID.sshPort,
                    MachineEditorFieldID.sshPassword,
                    MachineEditorFieldID.remoteCommand,
                    MachineEditorFieldID.waypipeEnabled
                ))
            } else if (state.isVirtualMachine) {
                fields.append(MachineEditorFieldID.vmSubtype)
            } else if (state.isContainer) {
                fields.append(MachineEditorFieldID.containerSubtype)
            }
            fields.append(MachineEditorFieldID.inputProfile)
            return fields.sref()
        }

        fun metadata(for_: MachineEditorFieldID): MachineEditorFieldMetadata {
            val field = for_
            when (field) {
                MachineEditorFieldID.name_ -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.name_, label = "Name", helperText = "Display name for this machine profile.", required = true)
                MachineEditorFieldID.type -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.type, label = "Type", helperText = "Select native or remote session mode.", required = true)
                MachineEditorFieldID.launcher -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.launcher, label = "Wayland Client", helperText = "Launcher used for local native sessions.")
                MachineEditorFieldID.sshHost -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.sshHost, label = "Host", helperText = "Remote host or IP address.", required = true)
                MachineEditorFieldID.sshUser -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.sshUser, label = "Username", helperText = "SSH username.", required = true)
                MachineEditorFieldID.sshPort -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.sshPort, label = "Port", helperText = "SSH port (1-65535).", required = true)
                MachineEditorFieldID.sshPassword -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.sshPassword, label = "Password", helperText = "Optional when key auth is used.")
                MachineEditorFieldID.remoteCommand -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.remoteCommand, label = "Remote Command", helperText = "Command to execute after SSH session starts.")
                MachineEditorFieldID.vmSubtype -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.vmSubtype, label = "VM Type", helperText = "Virtualization backend/profile name.", required = true)
                MachineEditorFieldID.containerSubtype -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.containerSubtype, label = "Container Type", helperText = "Container runtime/profile name.", required = true)
                MachineEditorFieldID.inputProfile -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.inputProfile, label = "Input Profile", helperText = "Input behavior profile.", required = true)
                MachineEditorFieldID.bundledAppID -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.bundledAppID, label = "Bundled App", helperText = "Bundled native app identifier.")
                MachineEditorFieldID.useBundledApp -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.useBundledApp, label = "Use Bundled App")
                MachineEditorFieldID.waypipeEnabled -> return MachineEditorFieldMetadata(id = MachineEditorFieldID.waypipeEnabled, label = "Waypipe Enabled")
            }
        }

        fun validate(state: MachineEditorState): Array<MachineEditorValidationIssue> {
            var issues: Array<MachineEditorValidationIssue> = arrayOf()
            if (state.name.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                issues.append(MachineEditorValidationIssue.missingName)
            }
            if (state.isSSH) {
                if (state.sshHost.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                    issues.append(MachineEditorValidationIssue.missingSSHHost)
                }
                if (state.sshUser.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                    issues.append(MachineEditorValidationIssue.missingSSHUser)
                }
                val port_0 = Int(state.sshPortText)
                if ((port_0 == null) || !(1..65535).contains(port_0)) {
                    issues.append(MachineEditorValidationIssue.invalidSSHPort)
                    return issues.sref()
                }
            }
            if (state.isVirtualMachine && state.vmSubtype.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                issues.append(MachineEditorValidationIssue.missingVMSubtype)
            }
            if (state.isContainer && state.containerSubtype.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                issues.append(MachineEditorValidationIssue.missingContainerSubtype)
            }
            return issues.sref()
        }

        fun normalizedPort(from: MachineEditorState): Int {
            val state = from
            return Int(state.sshPortText) ?: 22
        }
    }
}
