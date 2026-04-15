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

    public init() {}

    public func connect(machineId: String) -> MachineSession {
        var session = MachineSession(machineId: machineId, status: .connecting)
        session.status = .connected
        sessions = sessions + [session]
        activeSessionId = session.id
        return session
    }

    public func disconnect(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var next = sessions
        next[idx].status = .disconnected
        sessions = next
        if activeSessionId == sessionId {
            activeSessionId = sessions.first(where: { $0.status == .connected })?.id
        }
    }

    public func openExtraWindow(sessionId: UUID) {
        _ = sessionId
        // Implemented on Android/iPad platform layers.
    }

    public func notifyFramePresented(sessionId: UUID) {
        _ = sessionId
        framePresentedCount += 1
    }

    public func notifyClientConnected(sessionId: UUID) {
        _ = sessionId
        connectedClientCount += 1
    }
}
