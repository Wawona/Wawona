import Combine
import Foundation

public struct MachineSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var machineId: String
    public var status: MachineStatus
    public var bytesSent: Int64
    public var bytesReceived: Int64

    public init(
        id: UUID = UUID(),
        machineId: String,
        status: MachineStatus = .disconnected,
        bytesSent: Int64 = 0,
        bytesReceived: Int64 = 0
    ) {
        self.id = id
        self.machineId = machineId
        self.status = status
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
    }
}

@MainActor
public final class SessionOrchestrator: ObservableObject {
    @Published public private(set) var sessions: [MachineSession] = []
    @Published public private(set) var activeSessionId: UUID?
    @Published public private(set) var framePresentedCount: Int = 0
    @Published public private(set) var connectedClientCount: Int = 0

    public init() {
        RustDomainClient.bootstrapIfNeeded()
        refreshFromRust()
    }

    public func connect(machineId: String) -> MachineSession {
        let previousIDs = Set(sessions.map(\.id))
        guard RustDomainClient.dispatch([
            "type": "connect",
            "machine_id": machineId,
        ]) else {
            return MachineSession(machineId: machineId, status: .error)
        }
        refreshFromRust()
        return sessions.first(where: { !previousIDs.contains($0.id) })
            ?? MachineSession(machineId: machineId, status: .error)
    }

    public func markFailed(machineId: String, reason: String = "Connect failed") -> MachineSession {
        let previousIDs = Set(sessions.map(\.id))
        guard RustDomainClient.dispatch([
            "type": "connection_failed",
            "machine_id": machineId,
            "reason": reason,
        ]) else {
            return MachineSession(machineId: machineId, status: .error)
        }
        refreshFromRust()
        return sessions.first(where: { !previousIDs.contains($0.id) })
            ?? MachineSession(machineId: machineId, status: .error)
    }

    public func disconnect(sessionId: UUID) {
        if RustDomainClient.dispatch([
            "type": "disconnect",
            "session_id": sessionId.uuidString.lowercased(),
        ], persistDurable: false) {
            refreshFromRust()
        }
    }

    public func openExtraWindow(sessionId: UUID) {
        _ = sessionId
        // Implemented on Android/iPad platform layers.
    }

    public func notifyFramePresented(sessionId: UUID) {
        if RustDomainClient.dispatch([
            "type": "frame_presented",
            "session_id": sessionId.uuidString.lowercased(),
        ], persistDurable: false) {
            refreshFromRust()
        }
    }

    public func notifyClientConnected(sessionId: UUID) {
        if RustDomainClient.dispatch([
            "type": "client_connected",
            "session_id": sessionId.uuidString.lowercased(),
        ], persistDurable: false) {
            refreshFromRust()
        }
    }

    private func refreshFromRust() {
        guard let snapshot = RustDomainClient.snapshot(),
              let rawSessions = snapshot["sessions"],
              JSONSerialization.isValidJSONObject(rawSessions),
              let data = try? JSONSerialization.data(withJSONObject: rawSessions),
              let decoded = try? JSONDecoder().decode([MachineSession].self, from: data)
        else {
            return
        }
        sessions = decoded
        activeSessionId = (snapshot["activeSessionId"] as? String).flatMap(UUID.init(uuidString:))
        framePresentedCount = snapshot["framePresentedCount"] as? Int ?? 0
        connectedClientCount = snapshot["connectedClientCount"] as? Int ?? 0
    }
}
