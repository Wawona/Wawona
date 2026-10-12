import Foundation

extension Notification.Name {
    public static let WWNRelayGuestConsoleNeeded =
        Notification.Name("WWNRelayGuestConsoleNeededNotification")
}

@objc(WWNRelay)
public final class WWNRelay: NSObject {
    @objc public static let guestConsoleNeededNotification =
        Notification.Name.WWNRelayGuestConsoleNeeded

    @objc(sharedRelay) public static let sharedRelay = WWNRelay()

    private let lock = NSLock()
    private var backendsByMachineId: [String: String] = [:]
    private var handlesByMachineId: [String: String] = [:]

    #if os(iOS) || os(macOS)
    private var frameSource: DispatchSourceTimer?
    private var frameHandle: String?
    private var frameFails = 0
    private var framePresents = 0
    #endif

    private override init() {
        super.init()
    }

    @objc(nixEditorDocument:source:)
    public static func nixEditorDocument(_ name: String, source: String?) -> String? {
        var out: UnsafeMutablePointer<CChar>?
        let rc: Int32 = name.withCString { n in
            if let source {
                return source.withCString { RelayABI.nixEditor(n, $0, &out) }
            }
            return RelayABI.nixEditor(n, nil, &out)
        }
        guard rc == 0, let out else { return nil }
        defer { RelayABI.stringFree(out) }
        return String(cString: out)
    }

    @objc(startProfile:error:)
    public func startProfile(_ profile: WWNMachineProfile, error: NSErrorPointer) -> Bool {
        guard let kind = Self.kind(for: profile), !kind.isEmpty else {
            error?.pointee = NSError(
                domain: "WWNRelay", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Relay only starts vm, container, or wasm kinds."]
            )
            return false
        }

        // One live StaticCpu per machineId. Re-entry (AUTO_START + UI Start)
        // must NOT stop+restart: tearing down vsock 1024 mid-boot leaves guest
        // waypipe with `No wl_shm` / `ECONNRESET` and AUTH never lands.
        // Idempotent success if this machine already owns a session.
        let machineId = profile.machineId
        if !machineId.isEmpty, hasOwnedSession(forMachineId: machineId) {
            RelaySceneLog.write(
                "relay_start skip re-entry machineId=\(machineId)"
            )
            NSLog(
                "[WWNRelay] startProfile skip re-entry machineId=%@",
                machineId
            )
            return true
        }

        // Claim before long relay_start (16G rootfs SHA256). Parallel connect
        // during hash must see hasOwnedSession and skip, not stopAll mid-start.
        if !machineId.isEmpty {
            let claimed = lock.withLock { () -> Bool in
                if handlesByMachineId[machineId] != nil { return false }
                handlesByMachineId[machineId] = ""
                return true
            }
            if !claimed {
                RelaySceneLog.write(
                    "relay_start skip re-entry (claim race) machineId=\(machineId)"
                )
                return true
            }
        }

        let spec = Self.specJSON(profile: profile, kind: kind)
        var backendOut: UnsafeMutablePointer<CChar>?
        let resolveRc = spec.withCString { RelayABI.resolveBackend($0, &backendOut) }
        let backend = RelayABI.takeString(backendOut)

        if resolveRc == -1 {
            if !machineId.isEmpty {
                lock.withLock { handlesByMachineId.removeValue(forKey: machineId) }
            }
            error?.pointee = NSError(
                domain: "WWNRelay", code: 2,
                userInfo: [NSLocalizedDescriptionKey: backend ?? "Relay forbids this backend (no QEMU, no UTM)."]
            )
            return false
        }
        if resolveRc == -2 {
            if !machineId.isEmpty {
                lock.withLock { handlesByMachineId.removeValue(forKey: machineId) }
            }
            error?.pointee = NSError(
                domain: "WWNRelay", code: 3,
                userInfo: [NSLocalizedDescriptionKey: backend ?? "Relay backend is planned. Fail closed. No QEMU."]
            )
            return false
        }
        if !machineId.isEmpty, let backend, !backend.isEmpty {
            lock.withLock { backendsByMachineId[machineId] = backend }
        }

        RelaySceneLog.write("relay_start begin kind=\(kind) backend=\(backend ?? "(nil)")")
        var handleOut: UnsafeMutablePointer<CChar>?
        let startRc = spec.withCString { RelayABI.start($0, &handleOut) }
        let handleOrError = RelayABI.takeString(handleOut)
        RelaySceneLog.write("relay_start done rc=\(startRc) handle=\(handleOrError ?? "(null)")")

        guard startRc == 0 else {
            if !machineId.isEmpty {
                lock.withLock {
                    handlesByMachineId.removeValue(forKey: machineId)
                    backendsByMachineId.removeValue(forKey: machineId)
                }
            }
            error?.pointee = NSError(
                domain: "WWNRelay", code: 4,
                userInfo: [NSLocalizedDescriptionKey: handleOrError?.isEmpty == false
                    ? handleOrError! : "Relay could not start this guest. No QEMU fallback."]
            )
            return false
        }

        if !machineId.isEmpty, let handle = handleOrError, !handle.isEmpty {
            lock.withLock { handlesByMachineId[machineId] = handle }
        }

        if kind == "wasm" { return true }

        guard let backend else {
            error?.pointee = NSError(domain: "WWNRelay", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Relay started an unknown backend `(nil)`. No legacy fallback."
            ])
            return false
        }

        let known = ["vz", "kvm-ch", "kvm-crosvm", "static-cpu"]
        guard known.contains(backend) else {
            error?.pointee = NSError(
                domain: "WWNRelay", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Relay started an unknown backend `\(backend)`. No legacy fallback."]
            )
            return false
        }

        if backend == "static-cpu" {
            #if os(iOS) || os(macOS)
            guard let handle = handleOrError else { return true }
            // Mode A present: shm importer → relay_copy_frame → IlandPresentEngine.
            // Importer and host_waypipe both consume vsock 1024; prefer importer.
            // Never attach host_waypipe first: that steals the listener and
            // leaves copy_frame empty forever (no Mode A SHM present log).
            let shmRc = handle.withCString { RelayABI.startShmImporter($0) }
            RelaySceneLog.write("relay_start_shm_importer rc=\(shmRc)")
            NSLog("[WWNRelay] relay_start_shm_importer rc=%d", shmRc)
            if shmRc != 0 {
                // Mode A present needs the SHM importer. Do not fall through to
                // host_waypipe: it consumes vsock 1024 and leaves copy_frame empty.
                #if os(iOS)
                _ = handle.withCString { RelayABI.stop($0) }
                lock.withLock {
                    handlesByMachineId.removeValue(forKey: profile.machineId)
                    backendsByMachineId.removeValue(forKey: profile.machineId)
                }
                error?.pointee = NSError(
                    domain: "WWNRelay", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Relay could not attach guest graphics."]
                )
                return false
                #else
                let transportRc = handle.withCString {
                    RelayABI.startHostWaypipe($0, wwn_waypipe_client_fd)
                }
                RelaySceneLog.write("relay_start_host_waypipe rc=\(transportRc)")
                if transportRc != 0 {
                    _ = handle.withCString { RelayABI.stop($0) }
                    lock.withLock {
                        handlesByMachineId.removeValue(forKey: profile.machineId)
                        backendsByMachineId.removeValue(forKey: profile.machineId)
                    }
                    error?.pointee = NSError(
                        domain: "WWNRelay", code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "Relay could not attach guest graphics."]
                    )
                    return false
                }
                #endif
            }
            // Pump copy_frame. SHM importer fills imported frames for Mode A.
            let hid = lock.withLock { handlesByMachineId[profile.machineId] } ?? handle
            startPresenting(handle: hid)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.framePresents == 0 else { return }
                self.startPresenting(handle: hid)
            }
            // Mode A pixels need IlandPresenter (CompositorHostView). Same
            // reveal as macOS microvm / compositor client-attach. AUTO_START
            // used to call connect without Machines Start, leaving presenter nil.
            let surfaceMachineId = profile.machineId
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("WWNShowSessionSurfaceNotification"),
                    object: nil,
                    userInfo: [
                        "machineId": surfaceMachineId,
                        "source": "relay-static-cpu",
                    ]
                )
            }
            #endif
            #if os(iOS)
            let machineId = profile.machineId
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .WWNRelayGuestConsoleNeeded,
                    object: nil,
                    userInfo: ["machineId": machineId, "source": "relay"]
                )
            }
            #endif
        }
        return true
    }

    @objc(consoleLogForMachineId:)
    public func consoleLog(forMachineId machineId: String) -> Data? {
        let handle = lock.withLock { handlesByMachineId[machineId] }
        guard let handle, !handle.isEmpty else { return nil }
        var length = 0
        guard handle.withCString({ RelayABI.copyLog($0, nil, 0, &length) }) == 0 else { return nil }
        if length == 0 { return Data() }
        var bytes = [UInt8](repeating: 0, count: length)
        let rc = bytes.withUnsafeMutableBytes { buf in
            handle.withCString { RelayABI.copyLog($0, buf.baseAddress?.assumingMemoryBound(to: UInt8.self), length, &length) }
        }
        guard rc == 0 else { return nil }
        return Data(bytes)
    }

    @objc(stopProfileWithMachineId:)
    public func stopProfile(withMachineId machineId: String) {
        RelaySceneLog.write("relay_stopProfile begin machineId=\(machineId)")
        #if os(iOS) || os(macOS)
        stopFrameSource()
        frameHandle = nil
        #endif
        let handle = lock.withLock { handlesByMachineId[machineId] }
        // In-flight claim (""): drop claim only; relay_start not finished yet.
        if let handle, handle.isEmpty {
            lock.withLock {
                handlesByMachineId.removeValue(forKey: machineId)
                backendsByMachineId.removeValue(forKey: machineId)
            }
            RelaySceneLog.write("relay_stopProfile dropped claim machineId=\(machineId)")
            return
        }
        if let handle, !handle.isEmpty, handle.withCString({ RelayABI.stop($0) }) != 0 {
            RelaySceneLog.write("relay_stopProfile pending machineId=\(machineId) handle=\(handle)")
            return
        }
        lock.withLock {
            handlesByMachineId.removeValue(forKey: machineId)
            backendsByMachineId.removeValue(forKey: machineId)
        }
        WWNVirtualMachineRunner.sharedRunner.stopProfile(withMachineId: machineId)
        WWNContainerRunner.sharedRunner.stopProfile(withMachineId: machineId)
    }

    @objc(stopAll)
    public func stopAll() {
        RelaySceneLog.write("relay_stopAll begin count=\(lock.withLock { handlesByMachineId.count })")
        #if os(iOS) || os(macOS)
        stopFrameSource()
        frameHandle = nil
        #endif
        let snapshot = lock.withLock { handlesByMachineId }
        for (machineId, handle) in snapshot {
            if handle.isEmpty {
                lock.withLock {
                    handlesByMachineId.removeValue(forKey: machineId)
                    backendsByMachineId.removeValue(forKey: machineId)
                }
                continue
            }
            if handle.withCString({ RelayABI.stop($0) }) != 0 { continue }
            lock.withLock {
                handlesByMachineId.removeValue(forKey: machineId)
                backendsByMachineId.removeValue(forKey: machineId)
            }
        }
        WWNVirtualMachineRunner.sharedRunner.stopAll()
        WWNContainerRunner.sharedRunner.stopAll()
    }

    @objc public func hasOwnedSessions() -> Bool {
        lock.withLock { !handlesByMachineId.isEmpty }
    }

    @objc(hasOwnedSessionForMachineId:)
    public func hasOwnedSession(forMachineId machineId: String) -> Bool {
        lock.withLock {
            guard !machineId.isEmpty else { return false }
            // Empty string = in-flight claim during relay_start hash/boot.
            return handlesByMachineId[machineId] != nil
        }
    }

    @objc(resolvedBackendForMachineId:)
    public func resolvedBackend(forMachineId machineId: String) -> String? {
        lock.withLock { backendsByMachineId[machineId] }
    }

    #if os(iOS) || os(macOS)
    private func startPresenting(handle: String?) {
        RelaySceneLog.write("relay present enter handle=\(handle ?? "(nil)")")
        stopFrameSource()
        frameHandle = handle
        frameFails = 0
        framePresents = 0
        guard let handle, !handle.isEmpty else {
            NSLog("[WWNRelay] StaticCpu present: empty Relay handle")
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.pumpGuestFrame() }
        frameSource = timer
        timer.resume()
        pumpGuestFrame()
    }

    private func stopFrameSource() {
        frameSource?.cancel()
        frameSource = nil
    }

    private func pumpGuestFrame() {
        guard let handle = frameHandle, !handle.isEmpty else { return }
        var srcW: UInt32 = 0
        var srcH: UInt32 = 0
        // ERR_PLANNED (-2) means no frame yet; keep polling.
        let sizeRc = handle.withCString { RelayABI.copyFrame($0, nil, 0, &srcW, &srcH) }
        if sizeRc != 0 || srcW == 0 || srcH == 0 {
            return
        }
        let count = Int(srcW) * Int(srcH) * 4
        var pixels = [UInt8](repeating: 0, count: count)
        let copyRc = pixels.withUnsafeMutableBytes { buf in
            handle.withCString {
                RelayABI.copyFrame(
                    $0,
                    buf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    count,
                    &srcW,
                    &srcH
                )
            }
        }
        guard copyRc == 0 else { return }

        #if os(iOS) && WWN_MODE_B
        let modeBRc = pixels.withUnsafeBytes {
            wwn_modeb_desktop_present_bgra($0.baseAddress, srcW, srcH)
        }
        if modeBRc == 0 {
            frameFails = 0
            framePresents += 1
            return
        }
        #endif

        #if canImport(Metal) && !os(watchOS)
        guard let presenter = IlandPresenterObjC.activePresenterForDrain() else {
            frameFails += 1
            // First miss after pixels arrive: session surface not mounted
            // (AUTO_START used to skip showSessionSurface). Re-request mount.
            if frameFails == 1 || frameFails == 25 || frameFails == 100 {
                RelaySceneLog.write(
                    "relay present no IlandPresenter (session surface?) fails=\(frameFails)"
                )
                NSLog(
                    "[WWNRelay] Mode A SHM: no IlandPresenter (mount session surface) fails=%d",
                    frameFails
                )
                NotificationCenter.default.post(
                    name: Notification.Name("WWNShowSessionSurfaceNotification"),
                    object: nil,
                    userInfo: ["source": "relay-present-nil-presenter"]
                )
            }
            return
        }
        let stride = Int32(srcW) * 4
        let ok = pixels.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return false }
            return presenter.presentBGRAPixels(
                base,
                width: Int32(srcW),
                height: Int32(srcH),
                stride: stride,
                bottomUp: false
            )
        }
        if ok {
            frameFails = 0
            framePresents += 1
            if framePresents == 1 {
                RelaySceneLog.write("relay present Mode A SHM \(srcW)x\(srcH)")
                NSLog("[WWNRelay] Mode A SHM present \(srcW)x\(srcH)")
            }
        } else {
            frameFails += 1
        }
        #endif
    }
    #endif
}

private enum RelaySceneLog {
    static func write(_ line: String) {
        let path = "/tmp/wwn-modeb-scene.log"
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: path),
           let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
