import Foundation
import WawonaModel

/// App-target wiring for the platform-neutral WawonaModel framework.
/// All decisions remain in Rust; these closures only relay UTF-8 JSON.
@objc(WWNRustDomainTransportInstaller)
public final class WWNRustDomainTransportInstaller: NSObject {
    @objc public static func install() {
        RustDomainTransport.configure(
            snapshot: {
                WWNCompositorBridge.shared().domainSnapshotJSON()
            },
            durable: {
                WWNCompositorBridge.shared().domainDurableJSON()
            },
            resolvedMachine: { machineID in
                WWNCompositorBridge.shared()
                    .domainResolvedSettingsJSON(forMachineId: machineID)
            },
            resolvedProfile: { profileJSON in
                WWNCompositorBridge.shared().domainResolveProfileJSON(profileJSON)
            },
            normalizeTouchInput: { raw in
                WWNCompositorBridge.normalizedTouchInputType(raw)
            },
            dispatch: { intentJSON in
                WWNCompositorBridge.shared().dispatchDomainIntentJSON(intentJSON)
            }
        )
    }
}
