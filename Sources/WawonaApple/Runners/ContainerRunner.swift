import Foundation

/// OCI container supervision.
///
/// macOS: Apple Containerization via `wwn-containerd` (Relay macOS container
/// backend). Guest Wayland → waypipe vsock → Wawona compositor.
/// Other targets: Relay OCI-in-VM (`WWNRelay` / StaticCpu). Never QEMU/UTM.
@objc(WWNContainerRunner)
public final class WWNContainerRunner: NSObject {
    @objc(sharedRunner) public static let sharedRunner = WWNContainerRunner()

    #if os(macOS)
    private let lock = NSLock()
    private var tasksByMachineId: [String: Process] = [:]
    private var pollTimersByMachineId: [String: DispatchSourceTimer] = [:]
    #endif

    private override init() {
        super.init()
    }

    @objc(launchProfile:error:)
    public func launchProfile(_ profile: WWNMachineProfile, error: NSErrorPointer) -> Bool {
        #if os(macOS)
        do {
            let plan = try WWNContainerBootCommand.plan(for: profile)
            let machineId = profile.machineId ?? ""
            stopProfile(withMachineId: machineId)

            let fm = FileManager.default
            try? fm.removeItem(atPath: plan.readyFile)
            try? fm.removeItem(atPath: plan.doneFile)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: plan.executable)
            task.arguments = plan.arguments
            task.environment = plan.environment

            let out = Pipe()
            let err = Pipe()
            task.standardOutput = out
            task.standardError = err
            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    NSLog("[WWNContainerRunner] stdout: %@", line)
                }
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    NSLog("[WWNContainerRunner] stderr: %@", line)
                }
            }

            startMarkerPoll(machineId: machineId, ready: plan.readyFile, done: plan.doneFile)

            task.terminationHandler = { [weak self] finished in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lock.lock()
                    if self.tasksByMachineId[machineId] === finished {
                        self.tasksByMachineId.removeValue(forKey: machineId)
                    }
                    self.lock.unlock()
                    self.cleanupMarkers(machineId: machineId)
                    NotificationCenter.default.post(
                        name: Notification.Name("WWNContainerBackendDidStopNotification"),
                        object: nil,
                        userInfo: ["machineId": machineId]
                    )
                    NSLog(
                        "[WWNContainerRunner] exited machine=%@ status=%d",
                        machineId, finished.terminationStatus
                    )
                }
            }

            NSLog(
                "[WWNContainerRunner] launch machine=%@ desktop=%d exe=%@ args=%@",
                machineId, plan.desktopSession ? 1 : 0, plan.executable,
                plan.arguments.joined(separator: " ")
            )

            try task.run()

            let bridge = WWNCompositorBridge.sharedBridge
            bridge.pollAndHandleWindowEvents()
            for i in 1...4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(i)) {
                    bridge.pollAndHandleWindowEvents()
                }
            }

            if plan.desktopSession {
                DispatchQueue.main.async {
                    let userInfo: [AnyHashable: Any] = [
                        "machineId": machineId,
                        "source": "apple-containerization",
                    ]
                    NotificationCenter.default.post(
                        name: Notification.Name("WWNShowSessionSurfaceNotification"),
                        object: nil,
                        userInfo: userInfo
                    )
                }
            }

            lock.lock()
            tasksByMachineId[machineId] = task
            lock.unlock()
            return true
        } catch let launchError as NSError {
            error?.pointee = launchError
            return false
        } catch {
            error?.pointee = error as NSError
            return false
        }
        #else
        return WWNRelay.sharedRelay.startProfile(profile, error: error)
        #endif
    }

    @objc(stopProfileWithMachineId:)
    public func stopProfile(withMachineId machineId: String) {
        #if os(macOS)
        guard !machineId.isEmpty else { return }
        lock.lock()
        let task = tasksByMachineId.removeValue(forKey: machineId)
        lock.unlock()
        cleanupMarkers(machineId: machineId)
        if let task, task.isRunning {
            task.terminate()
        }
        #else
        WWNRelay.sharedRelay.stopProfile(withMachineId: machineId)
        #endif
    }

    @objc public func stopAll() {
        #if os(macOS)
        lock.lock()
        let ids = Array(tasksByMachineId.keys)
        lock.unlock()
        for id in ids {
            stopProfile(withMachineId: id)
        }
        #else
        WWNRelay.sharedRelay.stopAll()
        #endif
    }

    @objc(hasOwnedSessionForMachineId:)
    public func hasOwnedSession(forMachineId machineId: String) -> Bool {
        #if os(macOS)
        lock.lock()
        defer { lock.unlock() }
        guard let task = tasksByMachineId[machineId] else { return false }
        return task.isRunning
        #else
        return WWNRelay.sharedRelay.hasOwnedSession(forMachineId: machineId)
        #endif
    }

    #if os(macOS)
    private func cleanupMarkers(machineId: String) {
        let ready = WWNContainerBootCommand.markerPath(machineId: machineId, kind: "ready")
        let done = WWNContainerBootCommand.markerPath(machineId: machineId, kind: "done")
        try? FileManager.default.removeItem(atPath: ready)
        try? FileManager.default.removeItem(atPath: done)
        lock.lock()
        let timer = pollTimersByMachineId.removeValue(forKey: machineId)
        lock.unlock()
        timer?.cancel()
    }

    private func startMarkerPoll(machineId: String, ready: String, done: String) {
        cleanupMarkers(machineId: machineId)
        let queue = DispatchQueue(label: "com.aspauldingcode.wawona.container-markers")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
        var readyPosted = false
        var donePosted = false
        let fm = FileManager.default
        timer.setEventHandler {
            if !readyPosted, fm.fileExists(atPath: ready) {
                readyPosted = true
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("WWNContainerBackendDidBecomeReadyNotification"),
                        object: nil,
                        userInfo: ["machineId": machineId]
                    )
                }
            }
            if !donePosted, fm.fileExists(atPath: done) {
                donePosted = true
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("WWNContainerBackendDidStopNotification"),
                        object: nil,
                        userInfo: ["machineId": machineId]
                    )
                }
            }
        }
        timer.resume()
        lock.lock()
        pollTimersByMachineId[machineId] = timer
        lock.unlock()
    }
    #endif
}
