import Foundation

/// OCI container supervision. Same StaticCpu engine as VM (`WWNRelay`).
/// Host chrome calls here; Rust owns create/start/stop/kill over the guest
/// control channel (`relay-oci` `ContainerCommand`, including Kill).
/// Session park (hide surface → Machines) stays in `WWNMachinesViewModel.disconnect`.
@objc(WWNContainerRunner)
public final class WWNContainerRunner: NSObject {
    @objc(sharedRunner) public static let sharedRunner = WWNContainerRunner()

    private override init() {
        super.init()
    }

    @objc(launchProfile:error:)
    public func launchProfile(_ profile: WWNMachineProfile, error: NSErrorPointer) -> Bool {
        // Thin path: container kind uses Relay StaticCpu (OCI-in-VM). Never a
        // second engine. Never QEMU/UTM.
        return WWNRelay.sharedRelay.startProfile(profile, error: error)
    }

    @objc(stopProfileWithMachineId:)
    public func stopProfile(withMachineId machineId: String) {
        WWNRelay.sharedRelay.stopProfile(withMachineId: machineId)
    }

    @objc public func stopAll() {
        WWNRelay.sharedRelay.stopAll()
    }
}
