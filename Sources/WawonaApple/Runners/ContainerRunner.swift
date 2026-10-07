import Foundation

/// OCI container supervision. Product path is WWNRelay; Rust owns the host engine next.
@objc(WWNContainerRunner)
public final class WWNContainerRunner: NSObject {
    @objc(sharedRunner) public static let sharedRunner = WWNContainerRunner()

    private override init() {
        super.init()
    }

    @objc(launchProfile:error:)
    public func launchProfile(_ profile: WWNMachineProfile, error: NSErrorPointer) -> Bool {
        _ = profile
        error?.pointee = NSError(
            domain: "WWNContainerRunner",
            code: 200,
            userInfo: [NSLocalizedDescriptionKey:
                "Container supervision moves to the Relay Rust host. Use Machines Start."]
        )
        return false
    }

    @objc(stopProfileWithMachineId:)
    public func stopProfile(withMachineId machineId: String) {
        _ = machineId
    }

    @objc public func stopAll() {}
}
