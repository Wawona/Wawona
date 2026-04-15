package com.aspauldingcode.wawona

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.UUID

enum class MachineSessionState {
    IDLE,
    CONNECTING,
    CONNECTED,
    DEGRADED,
    DISCONNECTED,
    ERROR
}

fun MachineSessionState.toMachineStatus(): MachineStatus = when (this) {
    MachineSessionState.IDLE, MachineSessionState.DISCONNECTED -> MachineStatus.DISCONNECTED
    MachineSessionState.CONNECTING -> MachineStatus.CONNECTING
    MachineSessionState.CONNECTED -> MachineStatus.CONNECTED
    MachineSessionState.DEGRADED -> MachineStatus.DEGRADED
    MachineSessionState.ERROR -> MachineStatus.ERROR
}

data class MachineSession(
    val sessionId: String = UUID.randomUUID().toString(),
    val machineId: String,
    val machineName: String,
    val machineType: MachineType,
    val state: MachineSessionState = MachineSessionState.IDLE,
    val lastError: String? = null,
    val createdAtMs: Long = System.currentTimeMillis(),
    val updatedAtMs: Long = System.currentTimeMillis()
)

class SessionOrchestrator {
    private val _sessions = mutableStateListOf<MachineSession>()
    val sessions: List<MachineSession> get() = _sessions

    var activeSessionId by mutableStateOf<String?>(null)
        private set

    fun activeSession(): MachineSession? =
        sessions.firstOrNull { it.sessionId == activeSessionId }

    fun upsertSession(session: MachineSession) {
        val idx = _sessions.indexOfFirst { it.sessionId == session.sessionId }
        if (idx >= 0) _sessions[idx] = session else _sessions.add(session)
    }

    fun startSession(profile: MachineProfile): MachineSession {
        val existing = sessions.firstOrNull {
            it.machineId == profile.id && it.state == MachineSessionState.CONNECTED
        }
        if (existing != null) {
            activeSessionId = existing.sessionId
            return existing
        }

        val session = MachineSession(
            machineId = profile.id,
            machineName = profile.name,
            machineType = profile.type,
            state = MachineSessionState.CONNECTING
        )
        upsertSession(session)
        activeSessionId = session.sessionId
        return session
    }

    fun markConnected(sessionId: String) = mutateSession(sessionId) {
        copy(state = MachineSessionState.CONNECTED, lastError = null, updatedAtMs = System.currentTimeMillis())
    }

    fun markDegraded(sessionId: String, reason: String) = mutateSession(sessionId) {
        copy(state = MachineSessionState.DEGRADED, lastError = reason, updatedAtMs = System.currentTimeMillis())
    }

    fun markDisconnected(sessionId: String) = mutateSession(sessionId) {
        copy(state = MachineSessionState.DISCONNECTED, updatedAtMs = System.currentTimeMillis())
    }

    fun markError(sessionId: String, reason: String) = mutateSession(sessionId) {
        copy(state = MachineSessionState.ERROR, lastError = reason, updatedAtMs = System.currentTimeMillis())
    }

    fun setActiveSession(sessionId: String?) {
        activeSessionId = sessionId
    }

    fun removeSession(sessionId: String) {
        _sessions.removeAll { it.sessionId == sessionId }
        if (activeSessionId == sessionId) {
            activeSessionId = _sessions.lastOrNull()?.sessionId
        }
    }

    fun clearAllDisconnected() {
        _sessions.removeAll { it.state == MachineSessionState.DISCONNECTED }
        if (activeSessionId != null && _sessions.none { it.sessionId == activeSessionId }) {
            activeSessionId = _sessions.lastOrNull()?.sessionId
        }
    }

    fun statusForMachine(machineId: String): MachineStatus {
        val best = sessions
            .filter { it.machineId == machineId }
            .maxByOrNull { it.updatedAtMs }
            ?: return MachineStatus.DISCONNECTED
        return best.state.toMachineStatus()
    }

    private fun mutateSession(sessionId: String, transform: MachineSession.() -> MachineSession) {
        val idx = _sessions.indexOfFirst { it.sessionId == sessionId }
        if (idx >= 0) {
            _sessions[idx] = _sessions[idx].transform()
        }
    }
}
