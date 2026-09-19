import Foundation

/// Injectable transport boundary between the platform-neutral model framework
/// and the app target's Objective-C bridge. The closures only move JSON and do
/// not own product behavior.
public enum RustDomainTransport {
    public typealias StringProvider = () -> String?
    public typealias StringArgumentProvider = (String) -> String?
    public typealias Dispatcher = (String) -> Bool

    private static var snapshotProvider: StringProvider = { nil }
    private static var durableProvider: StringProvider = { nil }
    private static var resolvedMachineProvider: StringArgumentProvider = { _ in nil }
    private static var resolvedProfileProvider: StringArgumentProvider = { _ in nil }
    private static var touchInputNormalizer: (String?) -> String = { _ in "Multi-Touch" }
    private static var dispatcher: Dispatcher = { _ in false }

    public static func configure(
        snapshot: @escaping StringProvider,
        durable: @escaping StringProvider,
        resolvedMachine: @escaping StringArgumentProvider,
        resolvedProfile: @escaping StringArgumentProvider,
        normalizeTouchInput: @escaping (String?) -> String,
        dispatch: @escaping Dispatcher
    ) {
        snapshotProvider = snapshot
        durableProvider = durable
        resolvedMachineProvider = resolvedMachine
        resolvedProfileProvider = resolvedProfile
        touchInputNormalizer = normalizeTouchInput
        dispatcher = dispatch
    }

    static func snapshotJSON() -> String? { snapshotProvider() }
    static func durableJSON() -> String? { durableProvider() }
    static func resolvedMachineJSON(_ id: String) -> String? {
        resolvedMachineProvider(id)
    }
    static func resolvedProfileJSON(_ profile: String) -> String? {
        resolvedProfileProvider(profile)
    }
    static func normalizeTouchInput(_ raw: String?) -> String {
        touchInputNormalizer(raw)
    }
    static func dispatch(_ intent: String) -> Bool { dispatcher(intent) }
}
