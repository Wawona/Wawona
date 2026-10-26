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
    var onFailure: ((String) -> Void)?

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

    func writePaste(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.write(self.pasteWrapped(data))
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

    func stop() {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil { halt() } else { queue.sync { self.halt() } }
    }

    private func halt() {
        stopped = true
        owed.removeAll()
        pump?.cancel(); pump = nil
        if master >= 0 { IosShellABI.clearMaster(master); master = -1 }
        IosShellABI.stopShellSession()
        if let session { IosShellABI.sessionDestroy(session); self.session = nil }
        if let term { IosShellABI.termFree(term); self.term = nil }
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
                WWNTerminalCursorMode.observe(Data(buf.prefix(n)))
                buf.withUnsafeBufferPointer { IosShellABI.termFeed(term, $0.baseAddress, n) }
                writeReplies(term)
                continue
            }
            if n < 0, errno == EINTR { continue }
            if n < 0, errno == EAGAIN || errno == EWOULDBLOCK { break }
            exportScreen(); DispatchQueue.main.async { [weak self] in self?.onFailure?("Shell exited.") }; stop(); return
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
        publishTerm(term, onScreen: onScreen, onPictures: onPictures)
    }

    deinit { stop() }
}
final class IosLogTermSession {
    private var term: OpaquePointer?
    private var cols: UInt32 = 80
    private var rows: UInt32 = 28
    private let queue = DispatchQueue(label: "com.aspauldingcode.wawona.ios-log-term")
    private var stopped = false

    var onScreen: ((String) -> Void)?
    var onPictures: ((String) -> Void)?

    func start(cols: UInt32 = 80, rows: UInt32 = 28) {
        stop()
        stopped = false
        self.cols = max(20, cols)
        self.rows = max(8, rows)
        guard let term = IosShellABI.termNew(self.cols, self.rows) else { return }
        self.term = term
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
            self.exportScreen()
        }
    }

    func feed(_ text: String) {
        guard !text.isEmpty else { return }
        feed(Data(text.utf8))
    }

    func feed(_ data: Data) {
        guard !stopped, !data.isEmpty, let term else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped, let term = self.term else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                IosShellABI.termFeed(term, base, data.count)
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
        publishTerm(term, onScreen: onScreen, onPictures: onPictures)
    }

    deinit { stop() }
}

private func publishTerm(
    _ term: OpaquePointer?,
    onScreen: ((String) -> Void)?,
    onPictures: ((String) -> Void)?
) {
    guard let term else { return }
    let lines = takeTermString(IosShellABI.termLinesJson(term))
    let pictures = takeTermString(IosShellABI.termImagesJson(term))
    DispatchQueue.main.async {
        onScreen?(lines)
        onPictures?(pictures)
    }
}

private func takeTermString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr else { return "[]" }
    let text = String(cString: ptr)
    IosShellABI.termStringFree(ptr)
    return text
}
#endif
