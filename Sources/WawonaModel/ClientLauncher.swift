import Foundation

public struct ClientLauncher: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var executablePath: String
    public var arguments: [String]
    public var autoLaunch: Bool
    public var displayName: String

    public init(
        id: UUID = UUID(),
        name: String,
        executablePath: String,
        arguments: [String] = [],
        autoLaunch: Bool = false,
        displayName: String
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.autoLaunch = autoLaunch
        self.displayName = displayName
    }
}

public extension ClientLauncher {
#if os(iOS) || os(watchOS)
    static let presets: [ClientLauncher] = [
        ClientLauncher(name: "weston-simple-shm", executablePath: "weston-simple-shm", displayName: "Weston Simple SHM"),
        ClientLauncher(name: "weston-terminal", executablePath: "weston-terminal", displayName: "Weston Terminal"),
        ClientLauncher(name: "foot", executablePath: "foot", displayName: "Foot Terminal"),
        ClientLauncher(name: "weston", executablePath: "weston", displayName: "Weston")
    ]
#else
    static let presets: [ClientLauncher] = [
        ClientLauncher(name: "weston-simple-shm", executablePath: "weston-simple-shm", displayName: "Weston Simple SHM"),
        ClientLauncher(name: "weston-terminal", executablePath: "weston-terminal", displayName: "Weston Terminal"),
        ClientLauncher(name: "foot", executablePath: "foot", displayName: "Foot Terminal"),
        ClientLauncher(name: "weston", executablePath: "weston", displayName: "Weston")
    ]
#endif
}
