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
    private let queue = DispatchQueue(label: "com.aspauldingcode.wawona.ios-shell")
    private var cols: UInt32 = 80
    private var rows: UInt32 = 24
    private var stopped = false

    var onScreen: ((String) -> Void)?
    var onPictures: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    func start(cols: UInt32 = 80, rows: UInt32 = 24) {
        stop()
        stopped = false
        self.cols = max(20, cols)
        self.rows = max(8, rows)

        var err: NSError?
        if !WWNRootfsManager.ensureRootfsInstalled(&err) {
            onFailure?(err?.localizedDescription ?? "Rootfs install failed.")
            return
        }
        WWNRootfsManager.applyShellEnvironment()
        setenv("WAWONA_ZSH_IN_PROCESS", "1", 1)
        setenv("WAWONA_SHELL", "/usr/bin/zsh", 1)
        setenv("SHELL", "/usr/bin/zsh", 1)
        setenv("TERM", "xterm-256color", 1)

        IosShellABI.allowNewShellSession()

        guard let term = IosShellABI.termNew(self.cols, self.rows) else {
            onFailure?("Terminal screen failed to allocate.")
            return
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
            return
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
            self.cols = cols
            self.rows = rows
            IosShellABI.termResize(term, cols, rows)
            var ws = winsize()
            ws.ws_row = UInt16(rows)
            ws.ws_col = UInt16(cols)
            withUnsafePointer(to: &ws) { IosShellABI.setWinsize($0) }
            IosShellABI.kickShellDisplay()
            self.exportScreen()
        }
    }

    /// Bytes for the local VT only. The PTY does not see them.
    func feedLocal(_ data: Data) {
        guard !stopped, !data.isEmpty else { return }
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
            var reply = [UInt8](repeating: 0, count: 256)
            let n = reply.withUnsafeMutableBufferPointer { ptr in
                IosShellABI.termTakeReply(term, ptr.baseAddress, ptr.count)
            }
            if n > 0 {
                _ = reply.withUnsafeBytes { raw in
                    IosShellABI.inject(raw.baseAddress, n)
                }
            }
        }
    }

    func write(_ data: Data) {
        guard !stopped, !data.isEmpty else { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = IosShellABI.inject(base, data.count)
        }
    }

    /// Multiline input is a paste. Mode 2004 wraps it on the session queue.
    func writePaste(_ data: Data) {
        guard !stopped, !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            let wrapped: Data
            if let term = self.term {
                wrapped = data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return data
                    }
                    guard let ptr = IosShellABI.encodePaste(term, base, data.count) else {
                        return data
                    }
                    let text = String(cString: ptr)
                    IosShellABI.termStringFree(ptr)
                    return Data(text.utf8)
                }
            } else {
                wrapped = data
            }
            wrapped.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = IosShellABI.inject(base, wrapped.count)
            }
        }
    }

    func stop() {
        stopped = true
        pump?.cancel()
        pump = nil
        if master >= 0 {
            IosShellABI.clearMaster(master)
            master = -1
        }
        IosShellABI.stopShellSession()
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
        source.setEventHandler { [weak self] in
            self?.drainMaster()
        }
        source.setCancelHandler { }
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
                buf.withUnsafeBufferPointer { ptr in
                    IosShellABI.termFeed(term, ptr.baseAddress, n)
                }
                var reply = [UInt8](repeating: 0, count: 256)
                let rlen = reply.withUnsafeMutableBufferPointer { ptr in
                    IosShellABI.termTakeReply(term, ptr.baseAddress, ptr.count)
                }
                if rlen > 0 {
                    _ = reply.withUnsafeBytes { raw in
                        IosShellABI.inject(raw.baseAddress, rlen)
                    }
                }
                continue
            }
            break
        }
        exportScreen()
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
            self.cols = cols
            self.rows = rows
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
