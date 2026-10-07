import Foundation

/// iOS Linux VMs wait on Relay CPU. Fail closed. No QEMU in Mode A or Mode B.
@objc(WWNMobileVmEngine)
public final class WWNMobileVmEngine: NSObject {
    @objc(sharedEngine) public static let sharedEngine = WWNMobileVmEngine()

    private override init() {
        super.init()
    }

    @objc public func isEngineAvailable() -> Bool { false }

    @objc(launchProfileWithKernelPath:rootfsPath:memoryMB:error:)
    public func launchProfile(
        kernelPath: String,
        rootfsPath: String,
        memoryMB: UInt,
        error: NSErrorPointer
    ) -> Bool {
        launchProfile(
            kernelPath: kernelPath,
            rootfsPath: rootfsPath,
            memoryMB: memoryMB,
            ociBundlePath: nil,
            error: error
        )
    }

    @objc(launchProfileWithKernelPath:rootfsPath:memoryMB:ociBundlePath:error:)
    public func launchProfile(
        kernelPath: String,
        rootfsPath: String,
        memoryMB: UInt,
        ociBundlePath: String?,
        error: NSErrorPointer
    ) -> Bool {
        _ = kernelPath
        _ = rootfsPath
        _ = memoryMB
        _ = ociBundlePath
        error?.pointee = NSError(
            domain: "WWNMobileVmEngine",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey:
                "Use WWNRelay. iOS Linux guests start on Relay static CPU. No QEMU."]
        )
        return false
    }

    @objc public func stop() {}
}
