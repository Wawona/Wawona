import Foundation

/// Bitmask of Local Shell / WWN-ROOTFS features (mirrors WWNRootfsProvider.h).
public struct WWNRootfsCapabilities: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let none = WWNRootfsCapabilities([])
    public static let settings = WWNRootfsCapabilities(rawValue: 1 << 0)
    public static let browseUserFiles = WWNRootfsCapabilities(rawValue: 1 << 1)
    public static let importFile = WWNRootfsCapabilities(rawValue: 1 << 2)
    public static let resetDotfiles = WWNRootfsCapabilities(rawValue: 1 << 3)
    public static let reinstallSystemTree = WWNRootfsCapabilities(rawValue: 1 << 4)
    public static let iCloudSync = WWNRootfsCapabilities(rawValue: 1 << 5)
}

public let WWNRootfsCapabilityNone = WWNRootfsCapabilities.none
public let WWNRootfsCapabilitySettings = WWNRootfsCapabilities.settings
public let WWNRootfsCapabilityBrowseUserFiles = WWNRootfsCapabilities.browseUserFiles
public let WWNRootfsCapabilityImportFile = WWNRootfsCapabilities.importFile
public let WWNRootfsCapabilityResetDotfiles = WWNRootfsCapabilities.resetDotfiles
public let WWNRootfsCapabilityReinstallSystemTree = WWNRootfsCapabilities.reinstallSystemTree
public let WWNRootfsCapabilityICloudSync = WWNRootfsCapabilities.iCloudSync
