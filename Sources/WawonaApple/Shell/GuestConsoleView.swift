#if os(iOS) || os(tvOS) || os(visionOS)
import Darwin
import Foundation
import UIKit

@objc(WWNGuestConsoleView)
public final class WWNGuestConsoleView: UIView {
    @objc public private(set) var machineId: String = ""
    private let textView = UITextView()

    @objc(initWithMachineId:)
    public convenience init(machineId: String) {
        self.init(machineId: machineId, source: "local")
    }

    @objc(initWithMachineId:source:)
    public init(machineId: String, source: String) {
        self.machineId = machineId
        super.init(frame: .zero)
        _ = source
        #if !os(tvOS)
        textView.isEditable = false
        #endif
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc(appendOutput:)
    public func appendOutput(_ bytes: Data) {
        if let s = String(data: bytes, encoding: .utf8) {
            DispatchQueue.main.async {
                self.textView.text += s
            }
        }
    }

    @objc public func stop() {}
}

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

    @_silgen_name("wwn_term_export")
    static func termExport(
        _ term: OpaquePointer?,
        _ outLen: UnsafeMutablePointer<Int>?
    ) -> UnsafeMutablePointer<UInt8>?

    @_silgen_name("wwn_term_snapshot_free")
    static func termSnapshotFree(_ ptr: UnsafeMutablePointer<UInt8>?, _ len: Int)

    @_silgen_name("wwn_term_take_reply")
    static func termTakeReply(
        _ term: OpaquePointer?,
        _ buf: UnsafeMutablePointer<UInt8>?,
        _ cap: Int
    ) -> Int
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

    var onScreen: ((Data) -> Void)?
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

    func write(_ data: Data) {
        guard !stopped, !data.isEmpty else { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = IosShellABI.inject(base, data.count)
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
        let source = DispatchSource.makeReadSource(descriptor: fd, queue: queue)
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
        guard let term else { return }
        var len = 0
        guard let ptr = IosShellABI.termExport(term, &len), len > 0 else { return }
        let data = Data(bytes: ptr, count: len)
        IosShellABI.termSnapshotFree(ptr, len)
        DispatchQueue.main.async { [weak self] in
            self?.onScreen?(data)
        }
    }

    deinit { stop() }
}
#endif
