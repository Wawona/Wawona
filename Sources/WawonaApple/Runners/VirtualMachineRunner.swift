import Foundation

/// VM boot supervision. Product path is WWNRelay; this type keeps stop/cleanup hooks.
@objc(WWNVirtualMachineRunner)
public final class WWNVirtualMachineRunner: NSObject {
    @objc(sharedRunner) public static let sharedRunner = WWNVirtualMachineRunner()

    private override init() {
        super.init()
    }

    @objc(launchProfile:error:)
    public func launchProfile(_ profile: WWNMachineProfile, error: NSErrorPointer) -> Bool {
        _ = profile
        error?.pointee = NSError(
            domain: "WWNVirtualMachineRunner",
            code: 200,
            userInfo: [NSLocalizedDescriptionKey:
                "Virtual machine supervision moves to the Relay Rust host. Use Machines Start."]
        )
        return false
    }

    @objc(stopProfileWithMachineId:)
    public func stopProfile(withMachineId machineId: String) {
        _ = machineId
    }

    @objc public func stopAll() {}
}
