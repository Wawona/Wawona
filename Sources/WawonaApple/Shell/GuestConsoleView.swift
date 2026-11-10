#if os(iOS) || os(tvOS) || os(visionOS)
import Darwin
import Foundation

/// In-process Native Shell: `wwn_pty_session` + `wawona_zsh_main` + `wwn_term_*`.
enum IosShellABI {
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

    @_silgen_name("wwn_pty_ios_kick_shell_display")
    static func kickShellDisplay()

    @_silgen_name("wwn_term_new")
    static func termNew(_ cols: UInt32, _ rows: UInt32) -> OpaquePointer?

    @_silgen_name("wwn_term_free")
    static func termFree(_ term: OpaquePointer?)

    @_silgen_name("wwn_term_resize")
    static func termResize(_ term: OpaquePointer?, _ cols: UInt32, _ rows: UInt32)

    @_silgen_name("wwn_term_feed")
    static func termFeed(
        _ term: OpaquePointer?,
        _ bytes: UnsafePointer<UInt8>?,
        _ len: Int
    )

    @_silgen_name("wwn_term_lines_json")
    static func termLinesJson(_ term: OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    @_silgen_name("wwn_term_images_json")
    static func termImagesJson(_ term: OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    @_silgen_name("wwn_term_viewport")
    static func termViewport(
        _ term: OpaquePointer?,
        _ origin: UInt32,
        _ out: UnsafeMutablePointer<WwnTermCell>?,
        _ cap: UInt32,
        _ cols: UnsafeMutablePointer<UInt32>?,
        _ rows: UnsafeMutablePointer<UInt32>?
    ) -> UInt32

    @_silgen_name("wwn_term_origin")
    static func termOrigin(_ term: OpaquePointer?) -> UInt32

    @_silgen_name("wwn_term_set_cell_px")
    static func termSetCellPx(_ term: OpaquePointer?, _ width: UInt32, _ height: UInt32)

    @_silgen_name("wwn_term_string_free")
    static func termStringFree(_ ptr: UnsafeMutablePointer<CChar>?)

    @_silgen_name("wwn_term_encode_paste")
    static func encodePaste(
        _ term: OpaquePointer?,
        _ bytes: UnsafePointer<UInt8>?,
        _ len: Int
    ) -> UnsafeMutablePointer<CChar>?

    @_silgen_name("wwn_term_take_reply")
    static func termTakeReply(
        _ term: OpaquePointer?,
        _ buf: UnsafeMutablePointer<UInt8>?,
        _ cap: Int
    ) -> Int

    @_silgen_name("wwn_term_pointer")
    static func termPointer(
        _ term: OpaquePointer?, _ button: UInt8, _ col: UInt32, _ row: UInt32,
        _ pressed: Int32, _ motion: Int32
    )
}

final class IosShellSession {
    private var session: OpaquePointer?
    private var term: OpaquePointer?
    private var master: Int32 = -1
    private var pump: DispatchSourceRead?
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private let queue = DispatchQueue(label: "com.aspauldingcode.wawona.ios-shell")
    private var cols: UInt32 = 80
    private var rows: UInt32 = 24
    private var stopped = false
    private var owed = Data()
    private var retryArmed = false

    var onScreen: ((String) -> Void)?
    var onPictures: ((String) -> Void)?
    /// Viewport cells for Metal Present (`TerminalMetalPresent`).
    var onCells: (([WwnTermCell], UInt32, UInt32) -> Void)?
    /// Hard start failures only (rootfs, allocate, zsh start). Not PTY hangup.
    var onFailure: ((String) -> Void)?
    /// Soft EOF / hangup. Host restarts or paints `[session ended]`.
    var onEnded: (() -> Void)?

    func start(cols: UInt32 = 80, rows: UInt32 = 24) {
        queue.setSpecific(key: Self.queueKey, value: 1)
        stop()
        queue.sync { self.stopped = false; self.owed.removeAll() }
        (self.cols, self.rows) = (max(20, cols), max(8, rows))

        var err: NSError?
        if !WWNRootfsManager.ensureRootfsInstalled(&err) {
            onFailure?(err?.localizedDescription ?? "Rootfs install failed.")
            stop(); return
        }
        WWNRootfsManager.applyShellEnvironment()
        [("TERM", "xterm-256color"), ("WAWONA_ZSH_IN_PROCESS", "1"), ("WAWONA_SHELL", "/usr/bin/zsh"), ("SHELL", "/usr/bin/zsh")].forEach { setenv($0.0, $0.1, 1) }
        WWNTerminalCursorMode.observe(Data([0x18, 0x1B, 0x63]))
        // Drop a leftover hist lock from a prior Done hang before zsh starts.
        Self.clearZshHistoryLock()

        IosShellABI.allowNewShellSession()

        guard let term = IosShellABI.termNew(self.cols, self.rows) else {
            onFailure?("Terminal screen failed to allocate.")
            stop(); return
        }
        self.term = term

        var ws = winsize()
        ws.ws_row = UInt16(self.rows)
        ws.ws_col = UInt16(self.cols)
        withUnsafePointer(to: &ws) { IosShellABI.setWinsize($0) }

        let started: OpaquePointer? = "/usr/bin/zsh".withCString { path in
            withUnsafePointer(to: &ws) { wsPtr in
                IosShellABI.sessionStart(path, nil, nil, wsPtr)
            }
        }

        guard let started else {
            IosShellABI.termFree(term)
            self.term = nil
            onFailure?("Native Shell failed to start (in-process zsh).")
            stop(); return
        }
        session = started
        master = IosShellABI.masterFd(started)
        guard master >= 0 else {
            stop()
            onFailure?("Native Shell PTY master missing.")
            return
        }
        let flags = fcntl(master, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }
        IosShellABI.setMaster(master)
        armPump()
        exportScreen()
    }

    func resize(cols: UInt32, rows: UInt32, cellW: UInt32 = 8, cellH: UInt32 = 16) {
        let cols = min(512, max(20, cols))
        let rows = min(256, max(8, rows))
        queue.async { [weak self] in
            guard let self, !self.stopped, let term = self.term else { return }
            IosShellABI.termSetCellPx(term, cellW, cellH)
            guard cols != self.cols || rows != self.rows else { return }
            (self.cols, self.rows) = (cols, rows)
            IosShellABI.termResize(term, cols, rows)
            var ws = winsize()
            ws.ws_row = UInt16(rows)
            ws.ws_col = UInt16(cols)
            withUnsafePointer(to: &ws) { IosShellABI.setWinsize($0) }
            IosShellABI.kickShellDisplay()
            self.exportScreen()
        }
    }

    func feedLocal(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped, let term = self.term else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                IosShellABI.termFeed(term, base, data.count)
            }
            self.exportScreen()
        }
    }

    func pointer(button: UInt8, col: UInt32, row: UInt32, pressed: Bool, motion: Bool) {
        queue.async { [weak self] in
            guard let self, !self.stopped, let term = self.term else { return }
            IosShellABI.termPointer(term, button, col, row, pressed ? 1 : 0, motion ? 1 : 0)
            self.writeReplies(term)
        }
    }

    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        let send = { self.injectPty(data) }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil { send() } else { queue.sync(execute: send) }
    }

    private func injectPty(_ data: Data) {
        guard !stopped else { return }
        owed.append(data)
        flushOwed()
    }

    private func flushOwed() {
        guard !stopped, !owed.isEmpty else { return }
        var sent = 0
        owed.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var spins = 0
            while sent < raw.count, spins < 8 {
                let n = IosShellABI.inject(base.advanced(by: sent), raw.count - sent)
                if n > 0 { sent += n; spins = 0 }
                else if errno == EINTR || errno == EAGAIN { spins += 1 } else if errno == EIO || errno == EPIPE || errno == EBADF { sent = raw.count } else { break }
            }
        }
        if sent > 0 { owed.removeFirst(min(sent, owed.count)) }
        guard !owed.isEmpty, !retryArmed else { return }
        retryArmed = true
        queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.retryArmed = false
            self?.flushOwed()
        }
    }

    /// `trailer` rides the same queue hop so a Return cannot overtake the paste.
    func writePaste(_ data: Data, trailer: Data = Data()) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.write(self.pasteWrapped(data) + trailer)
        }
    }

    private func pasteWrapped(_ data: Data) -> Data {
        guard let term else { return data }
        return data.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let ptr = IosShellABI.encodePaste(term, base, data.count) else { return data }
            defer { IosShellABI.termStringFree(ptr) }
            return Data(String(cString: ptr).utf8)
        }
    }

    /// Serializes `pthread_join` so Done's async stop and Start's sync stop
    /// cannot double-join the same shell thread.
    private static let stopJoinQueue = DispatchQueue(label: "wwn.ios.shell.stop")

    /// Stop the in-process shell. Join must run **off** the PTY drain queue
    /// and **off** the UI main thread when `joinOffMain` is set.
    ///
    /// Joining on `queue` deadlocks Done / Stop: `zexit`/`savehistfile` write
    /// the socketpair while the pump that drains it is starved behind
    /// `pthread_join`. Joining on main freezes tvOS Done behind
    /// `lockhistfile` (SHARE_HISTORY symlink lock keyed by host `getpid()`,
    /// so a leftover `.zsh_history.LOCK` never looks stale while Wawona is
    /// alive). Keep the pump alive until join returns. Clear the hist lock
    /// before waking zsh so `savehistfile` cannot spin.
    func stop(joinOffMain: Bool = false) {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            // Rare nested path: hop off the drain queue before joining.
            NSLog("IosShellSession: stop on drain queue; deferring")
            let hop = joinOffMain
                ? DispatchQueue.global(qos: .userInitiated)
                : DispatchQueue.main
            hop.async { [weak self] in self?.stop(joinOffMain: joinOffMain) }
            return
        }
        queue.sync { self.prepareHalt() }
        // Strong capture: the console drops its reference right after this
        // call. A weak capture lets deinit run on main mid-join.
        let work = {
            Self.clearZshHistoryLock()
            IosShellABI.stopShellSession()
            self.queue.sync { self.finishHalt() }
        }
        if joinOffMain && Thread.isMainThread {
            Self.stopJoinQueue.async(execute: work)
        } else {
            Self.stopJoinQueue.sync(execute: work)
        }
    }

    /// In-process zsh hist locks use `symlink` → `/pid-<getpid()>/host-…`.
    /// `getpid()` is the Wawona host, so a leftover LOCK never looks stale.
    static func clearZshHistoryLock() {
        guard let homeC = getenv("HOME") else { return }
        let home = String(cString: homeC)
        guard !home.isEmpty else { return }
        let lock = (home as NSString).appendingPathComponent(".zsh_history.LOCK")
        do {
            try FileManager.default.removeItem(atPath: lock)
            NSLog("IosShellSession: cleared %@", lock)
        } catch {
            // Missing lock is fine.
        }
    }

    private func prepareHalt() {
        stopped = true
        owed.removeAll()
        // Leave pump running so zsh exit writes do not fill the socketpair.
    }

    private func finishHalt() {
        pump?.cancel()
        pump = nil
        if master >= 0 {
            IosShellABI.clearMaster(master)
            master = -1
        }
        if let session {
            IosShellABI.sessionDestroy(session)
            self.session = nil
        }
        if let term {
            IosShellABI.termFree(term)
            self.term = nil
        }
    }

    private func armPump() {
        let fd = master
        guard fd >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drainMaster() }
        pump = source
        source.resume()
    }

    private func drainMaster() {
        guard !stopped, master >= 0, let term else { return }
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { raw in
                IosShellABI.ptyRead(master, raw.baseAddress, raw.count)
            }
            if n > 0 {
                let chunk = Data(buf.prefix(n))
                WWNTerminalCursorMode.observe(chunk)
                // Lab: prove whether MotD ESC (0x1b) reaches VT feed. Remove once
                // CSI paint is green on visionOS/tvOS Metal Present.
                if chunk.contains(0x1b) || chunk.contains(0x9b) {
                    let hex = chunk.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
                    NSLog("IosShellSession: pty→term ESC/C1 present n=%d head=%@", n, hex)
                } else if chunk.contains(UInt8(ascii: "[")) {
                    let hex = chunk.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
                    NSLog("IosShellSession: pty→term no ESC but '[' n=%d head=%@", n, hex)
                }
                chunk.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                    IosShellABI.termFeed(term, base, chunk.count)
                }
                writeReplies(term)
                continue
            }
            if n < 0, errno == EINTR { continue }
            if n < 0, errno == EAGAIN || errno == EWOULDBLOCK { break }
            // PTY hangup / soft-exit: not a start failure. Cancel the pump
            // (EOF stays readable forever) and let the host restart.
            exportScreen()
            let ended = onEnded
            // Already on the drain queue; shell thread is gone. Do not
            // pthread_join here. Reap off-queue, then notify: a restart
            // posted before the reap makes the reap join the new live zsh
            // and Start's sync stop() hangs main behind it (2026-11-05).
            stopped = true
            owed.removeAll()
            pump?.cancel()
            pump = nil
            if master >= 0 {
                IosShellABI.clearMaster(master)
                master = -1
            }
            let sessionPtr = session
            let termPtr = term
            session = nil
            self.term = nil
            Self.stopJoinQueue.async {
                IosShellABI.stopShellSession()
                if let sessionPtr { IosShellABI.sessionDestroy(sessionPtr) }
                IosShellABI.termFree(termPtr)
                DispatchQueue.main.async { ended?() }
            }
            return
        }
        exportScreen()
    }

    private func writeReplies(_ term: OpaquePointer) {
        var reply = [UInt8](repeating: 0, count: 256)
        while true {
            let rlen = reply.withUnsafeMutableBufferPointer { IosShellABI.termTakeReply(term, $0.baseAddress, $0.count) }
            if rlen == 0 { break }
            write(Data(reply.prefix(rlen)))
            if rlen < reply.count { break }
        }
    }

    private func exportScreen() {
        publishTerm(term, onScreen: onScreen, onPictures: onPictures, onCells: onCells)
    }

    deinit {
        // Never join here: deinit can run on main. stop() owns the join.
        stopped = true
        pump?.cancel()
        pump = nil
        if master >= 0 {
            IosShellABI.clearMaster(master)
            master = -1
        }
        let sessionPtr = session
        let termPtr = term
        guard sessionPtr != nil || termPtr != nil else { return }
        Self.stopJoinQueue.async {
            IosShellABI.stopShellSession()
            if let sessionPtr { IosShellABI.sessionDestroy(sessionPtr) }
            if let termPtr { IosShellABI.termFree(termPtr) }
        }
    }
}
final class IosLogTermSession {
    private var term: OpaquePointer?
    private var cols: UInt32 = 80
    private var rows: UInt32 = 28
    private let queue = DispatchQueue(label: "com.aspauldingcode.wawona.ios-log-term")
    private var stopped = false

    var onScreen: ((String) -> Void)?
    var onPictures: ((String) -> Void)?
    var onCells: (([WwnTermCell], UInt32, UInt32) -> Void)?

    func start(cols: UInt32 = 80, rows: UInt32 = 28) {
        stop()
        stopped = false
        // Guest serial / Relay log: never start under 80 columns.
        self.cols = max(80, cols)
        self.rows = max(8, rows)
        guard let term = IosShellABI.termNew(self.cols, self.rows) else { return }
        self.term = term
        exportScreen()
    }

    func resize(cols: UInt32, rows: UInt32, cellW: UInt32 = 8, cellH: UInt32 = 16) {
        let cols = min(512, max(80, cols))
        let rows = min(256, max(8, rows))
        queue.async { [weak self] in
            guard let self, !self.stopped, let term = self.term else { return }
            IosShellABI.termSetCellPx(term, cellW, cellH)
            guard cols != self.cols || rows != self.rows else { return }
            (self.cols, self.rows) = (cols, rows)
            IosShellABI.termResize(term, cols, rows)
            self.exportScreen()
        }
    }

    func feed(_ text: String) {
        guard !text.isEmpty else { return }
        feed(Data(text.utf8))
    }

    func feed(_ data: Data) {
        guard !stopped, !data.isEmpty, term != nil else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped, let liveTerm = self.term else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                IosShellABI.termFeed(liveTerm, base, data.count)
            }
            self.exportScreen()
        }
    }

    func stop() {
        stopped = true
        if let term {
            IosShellABI.termFree(term)
            self.term = nil
        }
    }

    private func exportScreen() {
        publishTerm(term, onScreen: onScreen, onPictures: onPictures, onCells: onCells)
    }

    deinit { stop() }
}

private func publishTerm(
    _ term: OpaquePointer?,
    onScreen: ((String) -> Void)?,
    onPictures: ((String) -> Void)?,
    onCells: (([WwnTermCell], UInt32, UInt32) -> Void)?
) {
    guard let term else { return }
    let lines = takeTermString(IosShellABI.termLinesJson(term))
    let pictures = takeTermString(IosShellABI.termImagesJson(term))
    let cellsPayload = dumpViewport(term)
    DispatchQueue.main.async {
        onScreen?(lines)
        onPictures?(pictures)
        if let cellsPayload {
            onCells?(cellsPayload.0, cellsPayload.1, cellsPayload.2)
        }
    }
}

private func dumpViewport(_ term: OpaquePointer) -> ([WwnTermCell], UInt32, UInt32)? {
    let origin = IosShellABI.termOrigin(term)
    let cap: UInt32 = 512 * 256
    var storage = [WwnTermCell](
        repeating: WwnTermCell(cp: 32, fg: 0xE8E8E8, bg: 0, attrs: 0),
        count: Int(cap)
    )
    var outCols: UInt32 = 0
    var outRows: UInt32 = 0
    let n = storage.withUnsafeMutableBufferPointer { buf -> UInt32 in
        IosShellABI.termViewport(
            term, origin, buf.baseAddress, cap, &outCols, &outRows
        )
    }
    let count = Int(n)
    guard count > 0, outCols > 0, outRows > 0 else { return nil }
    return (Array(storage.prefix(count)), outCols, outRows)
}

private func takeTermString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr else { return "[]" }
    let text = String(cString: ptr)
    IosShellABI.termStringFree(ptr)
    return text
}
#endif
