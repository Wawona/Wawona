import Foundation
import Testing
@testable import WawonaModel

private final class MockWatchCompanionTransport: WatchCompanionTransport {
    var isSupported: Bool = true
    var isPaired: Bool = true
    var isWatchAppInstalled: Bool = true
    var isReachable: Bool = false
    var activateCount = 0
    var lastURL: URL?
    var nextResult: WatchCompanionSendResult = .queued(fileName: "x.wasm")

    func activate() {
        activateCount += 1
    }

    func transferFile(from url: URL, metadata: [String: Any]) -> WatchCompanionSendResult {
        lastURL = url
        _ = metadata
        return nextResult
    }
}

@Test
func watchCompanionStatusReflectsUnpairedTransport() {
    let mock = MockWatchCompanionTransport()
    mock.isPaired = false
    let defaults = UserDefaults(suiteName: "wawona.tests.watchCompanion.unpaired")!
    defaults.removePersistentDomain(forName: "wawona.tests.watchCompanion.unpaired")
    let controller = WatchCompanionController(defaults: defaults, transport: mock)
    let status = controller.status()
    #expect(status.supported)
    #expect(!status.paired)
    #expect(status.summary.contains("No paired"))
}

@Test
func watchCompanionSendQueuesAndRecordsPrefs() throws {
    let mock = MockWatchCompanionTransport()
    mock.isReachable = true
    mock.nextResult = .queued(fileName: "wayland-shm.wasm")
    let suite = "wawona.tests.watchCompanion.send"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let controller = WatchCompanionController(defaults: defaults, transport: mock)
    controller.activate()
    #expect(mock.activateCount == 1)

    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("wayland-shm.wasm")
    try Data([0x00, 0x61, 0x73, 0x6D]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let result = controller.sendDocument(at: tmp)
    #expect(result == .queued(fileName: "wayland-shm.wasm"))
    #expect(mock.lastURL == tmp)
    #expect(defaults.string(forKey: WatchCompanionPrefs.lastTransferNameKey) == "wayland-shm.wasm")
    #expect(defaults.string(forKey: WatchCompanionPrefs.lastTransferStatusKey) == "queued")
    #expect(controller.status().lastTransferSummary.contains("wayland-shm.wasm"))
}

@Test
func watchCompanionSendFailureRecordsMessage() throws {
    let mock = MockWatchCompanionTransport()
    mock.nextResult = .failed(message: "No paired Apple Watch")
    let suite = "wawona.tests.watchCompanion.fail"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let controller = WatchCompanionController(defaults: defaults, transport: mock)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("x.wasm")
    try Data([0x00, 0x61, 0x73, 0x6D]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let result = controller.sendDocument(at: tmp)
    #expect(result == .failed(message: "No paired Apple Watch"))
    #expect(defaults.string(forKey: WatchCompanionPrefs.lastTransferStatusKey)?
        .contains("failed") == true)
}

@Test
func watchCompanionIngestReceivedFileCopiesToInbox() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("recv-\(UUID().uuidString).wasm")
    try Data([0x00, 0x61, 0x73, 0x6D]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let dest = WatchCompanionController.ingestReceivedFile(
        at: tmp,
        preferredName: "demo.wasm"
    )
    #expect(dest != nil)
    #expect(dest?.lastPathComponent == "demo.wasm")
    #expect(dest?.path.contains("Wawona/inbox") == true)
    if let dest {
        try? FileManager.default.removeItem(at: dest.deletingLastPathComponent())
    }
}
