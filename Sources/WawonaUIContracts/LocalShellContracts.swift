import Foundation

/// Cross-platform Local Shell / WWN-ROOTFS settings contract.
/// Platform UIs (UIKit, Compose, GTK) render from this model; native code fills snapshots.
public enum LocalShellMode: String, Sendable {
    case bundled
    case host
}

public struct LocalShellCapabilities: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let settings = LocalShellCapabilities(rawValue: 1 << 0)
    public static let browseUserFiles = LocalShellCapabilities(rawValue: 1 << 1)
    public static let importFile = LocalShellCapabilities(rawValue: 1 << 2)
    public static let resetDotfiles = LocalShellCapabilities(rawValue: 1 << 3)
    public static let reinstallSystemTree = LocalShellCapabilities(rawValue: 1 << 4)
    /// Optional iCloud Drive sync for shell HOME (Apple platforms, user opt-in).
    public static let iCloudSync = LocalShellCapabilities(rawValue: 1 << 5)
}

public enum LocalShellICloudSyncState: String, Sendable {
    case off
    case on
}

public struct LocalShellSnapshot: Sendable, Hashable {
    public var mode: LocalShellMode
    public var platformLabel: String
    public var filesRoot: String
    public var home: String
    public var localHome: String?
    public var systemRoot: String
    public var bundleTemplateVersion: String
    public var appliedTemplateVersion: String
    public var filesHint: String
    public var shellPath: String?
    public var iCloudSync: LocalShellICloudSyncState?
    public var iCloudStatus: String?

    public init(
        mode: LocalShellMode = .host,
        platformLabel: String = "",
        filesRoot: String = "",
        home: String = "",
        localHome: String? = nil,
        systemRoot: String = "",
        bundleTemplateVersion: String = "—",
        appliedTemplateVersion: String = "—",
        filesHint: String = "",
        shellPath: String? = nil,
        iCloudSync: LocalShellICloudSyncState? = nil,
        iCloudStatus: String? = nil
    ) {
        self.mode = mode
        self.platformLabel = platformLabel
        self.filesRoot = filesRoot
        self.home = home
        self.localHome = localHome
        self.systemRoot = systemRoot
        self.bundleTemplateVersion = bundleTemplateVersion
        self.appliedTemplateVersion = appliedTemplateVersion
        self.filesHint = filesHint
        self.shellPath = shellPath
        self.iCloudSync = iCloudSync
        self.iCloudStatus = iCloudStatus
    }

    public var templateStatus: String {
        if mode == .host {
            return "host shell"
        }
        let applied = appliedTemplateVersion.isEmpty ? "—" : appliedTemplateVersion
        return "bundle v\(bundleTemplateVersion) / installed v\(applied)"
    }
}

public enum LocalShellAction: Sendable {
    case browseUserFiles
    case importFile
    case resetDotfiles
    case reinstallSystemTree
    case setICloudSync(Bool)
    case copyPath(String)
}
