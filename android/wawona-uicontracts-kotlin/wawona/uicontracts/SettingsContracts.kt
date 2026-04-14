package wawona.uicontracts

import skip.lib.*
import skip.lib.Array

import skip.foundation.*

sealed class ConnectionSettingsIntent {
    class UpdateWaylandDisplayCase(val associated0: String): ConnectionSettingsIntent() {
    }
    class TestSSHConnectionCase: ConnectionSettingsIntent() {
    }
    class TestWaypipeCommandCase: ConnectionSettingsIntent() {
    }
    class RunDependencyDiagnosticsCase: ConnectionSettingsIntent() {
    }

    @androidx.annotation.Keep
    companion object {
        fun updateWaylandDisplay(associated0: String): ConnectionSettingsIntent = UpdateWaylandDisplayCase(associated0)
        val testSSHConnection: ConnectionSettingsIntent = TestSSHConnectionCase()
        val testWaypipeCommand: ConnectionSettingsIntent = TestWaypipeCommandCase()
        val runDependencyDiagnostics: ConnectionSettingsIntent = RunDependencyDiagnosticsCase()
    }
}

@androidx.annotation.Keep
enum class ConnectionSettingsFieldID(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CaseIterable, RawRepresentable<String> {
    waylandDisplay("waylandDisplay"),
    sshHost("sshHost"),
    sshUser("sshUser"),
    sshPort("sshPort"),
    sshPassword("sshPassword"),
    waypipeCommand("waypipeCommand"),
    diagnostics("diagnostics");

    @androidx.annotation.Keep
    companion object: CaseIterableCompanion<ConnectionSettingsFieldID> {
        fun init(rawValue: String): ConnectionSettingsFieldID? {
            return when (rawValue) {
                "waylandDisplay" -> ConnectionSettingsFieldID.waylandDisplay
                "sshHost" -> ConnectionSettingsFieldID.sshHost
                "sshUser" -> ConnectionSettingsFieldID.sshUser
                "sshPort" -> ConnectionSettingsFieldID.sshPort
                "sshPassword" -> ConnectionSettingsFieldID.sshPassword
                "waypipeCommand" -> ConnectionSettingsFieldID.waypipeCommand
                "diagnostics" -> ConnectionSettingsFieldID.diagnostics
                else -> null
            }
        }

        override val allCases: Array<ConnectionSettingsFieldID>
            get() = arrayOf(waylandDisplay, sshHost, sshUser, sshPort, sshPassword, waypipeCommand, diagnostics)
    }
}

fun ConnectionSettingsFieldID(rawValue: String): ConnectionSettingsFieldID? = ConnectionSettingsFieldID.init(rawValue = rawValue)

@Suppress("MUST_BE_INITIALIZED")
class ConnectionSettingsFieldMetadata: MutableStruct {
    var id: ConnectionSettingsFieldID
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

    constructor(id: ConnectionSettingsFieldID, label: String, helperText: String? = null, required: Boolean = false) {
        this.id = id
        this.label = label
        this.helperText = helperText
        this.required = required
    }

    private constructor(copy: MutableStruct) {
        @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as ConnectionSettingsFieldMetadata
        this.id = copy.id
        this.label = copy.label
        this.helperText = copy.helperText
        this.required = copy.required
    }

    override var supdate: ((Any) -> Unit)? = null
    override var smutatingcount = 0
    override fun scopy(): MutableStruct = ConnectionSettingsFieldMetadata(this as MutableStruct)

    override fun equals(other: Any?): Boolean {
        if (other !is ConnectionSettingsFieldMetadata) return false
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
class ConnectionSettingsState: MutableStruct {
    var waylandDisplay: String
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
    var waypipeCommand: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }
    var latestDiagnosticsSummary: String
        set(newValue) {
            willmutate()
            field = newValue
            didmutate()
        }

    constructor(waylandDisplay: String = "wayland-0", sshHost: String = "", sshUser: String = "", sshPortText: String = "22", sshPassword: String = "", waypipeCommand: String = "weston-terminal", latestDiagnosticsSummary: String = "") {
        this.waylandDisplay = waylandDisplay
        this.sshHost = sshHost
        this.sshUser = sshUser
        this.sshPortText = sshPortText
        this.sshPassword = sshPassword
        this.waypipeCommand = waypipeCommand
        this.latestDiagnosticsSummary = latestDiagnosticsSummary
    }

    private constructor(copy: MutableStruct) {
        @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as ConnectionSettingsState
        this.waylandDisplay = copy.waylandDisplay
        this.sshHost = copy.sshHost
        this.sshUser = copy.sshUser
        this.sshPortText = copy.sshPortText
        this.sshPassword = copy.sshPassword
        this.waypipeCommand = copy.waypipeCommand
        this.latestDiagnosticsSummary = copy.latestDiagnosticsSummary
    }

    override var supdate: ((Any) -> Unit)? = null
    override var smutatingcount = 0
    override fun scopy(): MutableStruct = ConnectionSettingsState(this as MutableStruct)

    override fun equals(other: Any?): Boolean {
        if (other !is ConnectionSettingsState) return false
        return waylandDisplay == other.waylandDisplay && sshHost == other.sshHost && sshUser == other.sshUser && sshPortText == other.sshPortText && sshPassword == other.sshPassword && waypipeCommand == other.waypipeCommand && latestDiagnosticsSummary == other.latestDiagnosticsSummary
    }

    override fun hashCode(): Int {
        var result = 1
        result = Hasher.combine(result, waylandDisplay)
        result = Hasher.combine(result, sshHost)
        result = Hasher.combine(result, sshUser)
        result = Hasher.combine(result, sshPortText)
        result = Hasher.combine(result, sshPassword)
        result = Hasher.combine(result, waypipeCommand)
        result = Hasher.combine(result, latestDiagnosticsSummary)
        return result
    }

    @androidx.annotation.Keep
    companion object {
    }
}

enum class ConnectionSettingsValidationIssue(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<String> {
    emptyWaylandDisplay("emptyWaylandDisplay"),
    emptySSHHost("emptySSHHost"),
    emptySSHUser("emptySSHUser"),
    invalidSSHPort("invalidSSHPort"),
    emptyWaypipeCommand("emptyWaypipeCommand");

    @androidx.annotation.Keep
    companion object {
        fun init(rawValue: String): ConnectionSettingsValidationIssue? {
            return when (rawValue) {
                "emptyWaylandDisplay" -> ConnectionSettingsValidationIssue.emptyWaylandDisplay
                "emptySSHHost" -> ConnectionSettingsValidationIssue.emptySSHHost
                "emptySSHUser" -> ConnectionSettingsValidationIssue.emptySSHUser
                "invalidSSHPort" -> ConnectionSettingsValidationIssue.invalidSSHPort
                "emptyWaypipeCommand" -> ConnectionSettingsValidationIssue.emptyWaypipeCommand
                else -> null
            }
        }
    }
}

fun ConnectionSettingsValidationIssue(rawValue: String): ConnectionSettingsValidationIssue? = ConnectionSettingsValidationIssue.init(rawValue = rawValue)

/// Declared as `struct` so Skip emits a normal Kotlin class (see `MachineEditorValidation` note).
class ConnectionSettingsValidation {

    @androidx.annotation.Keep
    companion object {
        fun metadata(for_: ConnectionSettingsFieldID): ConnectionSettingsFieldMetadata {
            val field = for_
            when (field) {
                ConnectionSettingsFieldID.waylandDisplay -> return ConnectionSettingsFieldMetadata(id = ConnectionSettingsFieldID.waylandDisplay, label = "Wayland Display", helperText = "Socket name used by compositor clients (for example: wayland-0).", required = true)
                ConnectionSettingsFieldID.sshHost -> return ConnectionSettingsFieldMetadata(id = ConnectionSettingsFieldID.sshHost, label = "SSH Host", required = true)
                ConnectionSettingsFieldID.sshUser -> return ConnectionSettingsFieldMetadata(id = ConnectionSettingsFieldID.sshUser, label = "SSH User", required = true)
                ConnectionSettingsFieldID.sshPort -> return ConnectionSettingsFieldMetadata(id = ConnectionSettingsFieldID.sshPort, label = "SSH Port", required = true)
                ConnectionSettingsFieldID.sshPassword -> return ConnectionSettingsFieldMetadata(id = ConnectionSettingsFieldID.sshPassword, label = "SSH Password")
                ConnectionSettingsFieldID.waypipeCommand -> return ConnectionSettingsFieldMetadata(id = ConnectionSettingsFieldID.waypipeCommand, label = "Waypipe Command", required = true)
                ConnectionSettingsFieldID.diagnostics -> return ConnectionSettingsFieldMetadata(id = ConnectionSettingsFieldID.diagnostics, label = "Diagnostics")
            }
        }

        fun validate(state: ConnectionSettingsState): Array<ConnectionSettingsValidationIssue> {
            var issues: Array<ConnectionSettingsValidationIssue> = arrayOf()
            if (state.waylandDisplay.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                issues.append(ConnectionSettingsValidationIssue.emptyWaylandDisplay)
            }
            if (state.sshHost.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                issues.append(ConnectionSettingsValidationIssue.emptySSHHost)
            }
            if (state.sshUser.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                issues.append(ConnectionSettingsValidationIssue.emptySSHUser)
            }
            val matchtarget_0 = Int(state.sshPortText)
            if (matchtarget_0 != null) {
                val p = matchtarget_0
                if ((1..65535).contains(p)) {
                    // valid
                } else {
                    issues.append(ConnectionSettingsValidationIssue.invalidSSHPort)
                }
            } else {
                issues.append(ConnectionSettingsValidationIssue.invalidSSHPort)
            }
            if (state.waypipeCommand.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines).isEmpty) {
                issues.append(ConnectionSettingsValidationIssue.emptyWaypipeCommand)
            }
            return issues.sref()
        }

        fun normalizedDisplay(state: ConnectionSettingsState): String {
            val trimmed = state.waylandDisplay.trimmingCharacters(in_ = CharacterSet.whitespacesAndNewlines)
            return if (trimmed.isEmpty) "wayland-0" else trimmed
        }

        fun normalizedSSHPort(state: ConnectionSettingsState): Int = Int(state.sshPortText) ?: 22
    }
}
