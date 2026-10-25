#if os(watchOS)
import Darwin
import Foundation

/// Live Wawona Terminal shells keyed by machine session. A shell belongs to
/// its session, not to the SwiftUI view: Tab Overview Focus dismisses and
/// re-presents `CompositorActiveView`, and that must reattach, not restart.
@MainActor
final class WatchNativeShellRegistry {
    static let shared = WatchNativeShellRegistry()

    private var shells: [UUID: WatchNativeShellSession] = [:]

    func attach(
        sessionId: UUID,
        onScreen: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) -> WatchNativeShellSession {
        if let shell = shells[sessionId], shell.isRunning {
            shell.onScreen = onScreen
            shell.onFailure = onFailure
            shell.republishScreen()
            return shell
        }
        let shell = WatchNativeShellSession()
        shell.onScreen = onScreen
        shell.onFailure = onFailure
        shells[sessionId] = shell
        shell.start()
        return shell
    }

    func detach(sessionId: UUID) {
        guard let shell = shells[sessionId] else { return }
        shell.onScreen = nil
        shell.onFailure = nil
    }

    func stop(sessionId: UUID) {
        shells.removeValue(forKey: sessionId)?.stop()
    }
}

/// In-process Wawona Terminal on watchOS: `wwn_pty` + `wawona_zsh_main` + `wwn_term`.
final class WatchNativeShellSession {
    /// One queue for every session: `wwn_pty` shell state is process-global,
    /// so a pending stop must finish before the next start touches it.
    private static let queue = DispatchQueue(label: "com.aspauldingcode.wawona.watch-shell")

    private var session: OpaquePointer?
    private var term: OpaquePointer?
    private var master: Int32 = -1
    private var pump: DispatchSourceRead?
    private var cols: UInt32 = 36
    private var rows: UInt32 = 10
    private var stopped = true

    var onScreen: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    var isRunning: Bool { !stopped }

    func start(cols: UInt32 = 36, rows: UInt32 = 10) {
        guard stopped, session == nil else { return }
        self.cols = max(16, cols)
        self.rows = max(4, rows)
        let failure = Self.queue.sync { startLocked() }
        if let failure {
            onFailure?(failure)
        }
    }

    private func startLocked() -> String? {
        WWNWatchShellEnvironment.apply()
        setenv("WAWONA_PTY_FAKE_TTY", "1", 1)
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wwn_pty_ios_force_fake_tty") {
            typealias ForceFakeTty = @convention(c) () -> Void
            unsafeBitCast(sym, to: ForceFakeTty.self)()
        }
        WatchShellABI.allowNewShellSession()

        guard let term = WatchShellABI.termNew(cols, rows) else {
            return "Terminal screen failed to allocate."
        }
        self.term = term
        WawonaTerminalScrollback.apply(to: term)

        var ws = winsize()
        ws.ws_row = UInt16(rows)
        ws.ws_col = UInt16(cols)
        withUnsafePointer(to: &ws) { WatchShellABI.setWinsize($0) }

        let started: OpaquePointer? = "/usr/bin/zsh".withCString { path in
            withUnsafePointer(to: &ws) { wsPtr in
                WatchShellABI.sessionStart(path, nil, nil, wsPtr)
            }
        }
        guard let started else {
            WatchShellABI.termFree(term)
            self.term = nil
            return "Native Shell failed to start (in-process zsh)."
        }
        session = started
        master = WatchShellABI.masterFd(started)
        guard master >= 0 else {
            teardownLocked()
            return "Native Shell PTY master missing."
        }
        stopped = false
        let flags = fcntl(master, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }
        WatchShellABI.setMaster(master)
        armPump()
        exportScreen()
        return nil
    }

    func write(_ text: String) {
        guard !stopped, !text.isEmpty else { return }
        let data = Data(text.utf8)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = WatchShellABI.inject(base, data.count)
        }
    }

    func republishScreen() {
        Self.queue.async { [weak self] in self?.exportScreen() }
    }

    /// Never blocks the caller. Joining the zsh thread happens on the shell
    /// queue; the main thread must stay responsive or the watchdog kills us.
    func stop() {
        stopped = true
        onScreen = nil
        onFailure = nil
        Self.queue.async { [self] in teardownLocked() }
    }

    private func teardownLocked() {
        stopped = true
        pump?.cancel()
        pump = nil
        if master >= 0 {
            WatchShellABI.clearMaster(master)
            master = -1
        }
        if let session {
            WatchShellABI.stopShellSession()
            WatchShellABI.sessionDestroy(session)
            self.session = nil
        }
        if let term {
            WatchShellABI.termFree(term)
            self.term = nil
        }
    }

    private func armPump() {
        let fd = master
        guard fd >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: Self.queue)
        source.setEventHandler { [weak self] in
            self?.drainMaster()
        }
        pump = source
        source.resume()
    }

    private func drainMaster() {
        guard !stopped, master >= 0, let term else { return }
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { raw in
                WatchShellABI.ptyRead(master, raw.baseAddress, raw.count)
            }
            if n > 0 {
                buf.withUnsafeBufferPointer { ptr in
                    WatchShellABI.termFeed(term, ptr.baseAddress, n)
                }
                continue
            }
            if n < 0, errno == EINTR { continue }
            if n == 0 || (n < 0 && errno != EAGAIN) {
                // Shell side closed: the master stays readable at EOF forever.
                // (`n < 0` other than EAGAIN means the fd is gone.)
                pump?.cancel()
                pump = nil
            }
            break
        }
        exportScreen()
    }

    private func exportScreen() {
        guard let term else { return }
        let ptr = WatchShellABI.termLinesJson(term)
        let text: String
        if let ptr {
            text = String(cString: ptr)
            WatchShellABI.termStringFree(ptr)
        } else {
            text = "[]"
        }
        DispatchQueue.main.async { [weak self] in
            self?.onScreen?(text)
        }
    }

    deinit {
        pump?.cancel()
        let session = session
        let term = term
        let master = master
        guard session != nil || term != nil else { return }
        Self.queue.async {
            if master >= 0 { WatchShellABI.clearMaster(master) }
            if let session {
                WatchShellABI.stopShellSession()
                WatchShellABI.sessionDestroy(session)
            }
            if let term { WatchShellABI.termFree(term) }
        }
    }
}

enum WatchShellABI {
    @_silgen_name("wwn_pty_session_start")
    static func sessionStart(
        _ shellPath: UnsafePointer<CChar>?,
        _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        _ envp: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        _ ws: UnsafePointer<winsize>?
    ) -> OpaquePointer?

    @_silgen_name("wwn_pty_session_master_fd")
    static func masterFd(_ session: OpaquePointer?) -> Int32

    @_silgen_name("wwn_pty_session_destroy")
    static func sessionDestroy(_ session: OpaquePointer?)

    @_silgen_name("wwn_pty_read")
    static func ptyRead(_ fd: Int32, _ buf: UnsafeMutableRawPointer?, _ len: Int) -> Int

    @_silgen_name("wwn_pty_ios_stop_shell_session")
    static func stopShellSession()

    @_silgen_name("wwn_pty_ios_allow_new_shell_session")
    static func allowNewShellSession()

    @_silgen_name("wwn_ios_terminal_set_master")
    static func setMaster(_ fd: Int32)

    @_silgen_name("wwn_ios_terminal_clear_master")
    static func clearMaster(_ fd: Int32)

    @_silgen_name("wwn_ios_terminal_inject")
    static func inject(_ buf: UnsafeRawPointer?, _ len: Int) -> Int

    @_silgen_name("wwn_pty_tty_shim_set_winsize")
    static func setWinsize(_ ws: UnsafePointer<winsize>?)

    @_silgen_name("wwn_term_new")
    static func termNew(_ cols: UInt32, _ rows: UInt32) -> OpaquePointer?

    @_silgen_name("wwn_term_free")
    static func termFree(_ term: OpaquePointer?)

    @_silgen_name("wwn_term_feed")
    static func termFeed(
        _ term: OpaquePointer?,
        _ bytes: UnsafePointer<UInt8>?,
        _ len: Int
    )

    @_silgen_name("wwn_term_lines_json")
    static func termLinesJson(_ term: OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    @_silgen_name("wwn_term_string_free")
    static func termStringFree(_ ptr: UnsafeMutablePointer<CChar>?)
}
#endif
