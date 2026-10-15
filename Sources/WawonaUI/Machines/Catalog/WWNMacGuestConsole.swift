#if os(macOS)
import AppKit
import Darwin

/// AppKit host for Wawona Terminal on macOS Start. Every machine Start
/// presents this window with `$ argv` and streamed CLI logs. Close reveals
/// the compositor (Focus). No auto-dismiss on first frame.
@objc final class WWNMacGuestConsole: NSObject, NSWindowDelegate {
  @objc static let shared = WWNMacGuestConsole()

  private var window: NSWindow?
  private var surface: WWNTermSurface?
  private let pumpQueue = DispatchQueue(label: "com.aspauldingcode.wawona.mac-guest-console")
  private var pumpTimer: DispatchSourceTimer?
  private var launchLogObserver: NSObjectProtocol?
  private var fed = 0
  private var machineId = ""
  private var source = "relay"
  private var master: Int32 = -1
  private var shellPid: pid_t = -1
  private var shellReader: DispatchSourceRead?
  private var stopped = false

  func present(machineId: String, source: String) {
    guard !machineId.isEmpty else { return }
    if let existing = window, self.machineId == machineId {
      existing.makeKeyAndOrderFront(nil)
      focusShellKeys()
      return
    }
    dismiss(machineId: self.machineId)
    self.machineId = machineId
    self.source = source
    self.fed = 0
    self.stopped = false

    let surface = WWNTermSurface(frame: NSRect(x: 0, y: 0, width: 780, height: 480))
    surface.onReply = { [weak self] data in
      self?.writeMaster(data)
    }
    surface.onResize = { [weak self] cols, rows in
      self?.setWinsize(cols: cols, rows: rows)
    }
    surface.onTitle = { [weak self] title in
      self?.window?.title = title
    }
    self.surface = surface

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false)
    // ARC owns this window via `self.window`. Default releasedWhenClosed
    // would deallocate on close while we still hold the reference, then the
    // next Start hits objc_retain on a dangling NSWindow (SIGSEGV).
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.title = "Wawona Terminal"
    window.contentView = surface
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window

    if source == "shell" {
      startShell()
      focusShellKeys()
    } else {
      let banner: String
      switch source {
      case "ssh":
        banner = "SSH session starting.\n"
      case "client":
        banner = clientBanner(machineId: machineId)
      default:
        banner = "Wawona Terminal\n"
      }
      surface.feed(Data(banner.utf8))
    }
    startLaunchLogObserver()
    startPump()
  }

  func dismiss(machineId: String) {
    if !self.machineId.isEmpty, machineId != self.machineId { return }
    stopped = true
    if let obs = launchLogObserver {
      NotificationCenter.default.removeObserver(obs)
      launchLogObserver = nil
    }
    pumpTimer?.cancel()
    pumpTimer = nil
    if shellPid > 0 {
      kill(shellPid, SIGTERM)
      shellPid = -1
    }
    shellReader?.cancel()
    shellReader = nil
    if master >= 0 {
      close(master)
      master = -1
    }
    if let window {
      window.delegate = nil
      window.orderOut(nil)
    }
    window = nil
    surface = nil
    self.machineId = ""
  }

  func windowWillClose(_ notification: Notification) {
    let closingId = machineId
    dismiss(machineId: closingId)
    guard !closingId.isEmpty else { return }
    WWNMachineProfileStore.setActiveMachineId(closingId)
    WWNMainWindowRouter.shared.showSessionSurface()
  }

  private func clientBanner(machineId: String) -> String {
    guard let profile = WWNMachineProfileStore.profile(byId: machineId) else {
      return "Wawona Terminal\n"
    }
    let prefs = WWNPreferencesManager.sharedManager()
    let kind = WWNNativeShellConfiguration.kind(for: profile)
    if kind == kWWNNativeShellKindWaypipe || profile.type == kWWNMachineTypeSSHWaypipe {
      let preview = WWNWaypipeRunner.sharedRunner().generateWaypipePreviewString(prefs)
      return "$ \(preview)\n"
    }
    let client = WWNMachineSessionBridge.nativeClientId(forProfile: profile) ?? "client"
    let display = WWNCompositorBridge.sharedBridge.socketName()
    return "$ wwn-exec \(client)\nWAYLAND_DISPLAY=\(display.isEmpty ? "wayland-0" : display)\n"
  }

  private func startLaunchLogObserver() {
    if let obs = launchLogObserver {
      NotificationCenter.default.removeObserver(obs)
    }
    launchLogObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("WWNClientLaunchLogNotification"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let self, !self.stopped else { return }
      guard self.source == "client" || self.source == "relay" || self.source == "ssh"
      else { return }
      if let line = note.userInfo?["line"] as? String, !line.isEmpty {
        self.append(Data(line.utf8))
      }
    }
  }

  private func startPump() {
    let timer = DispatchSource.makeTimerSource(queue: pumpQueue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(50))
    timer.setEventHandler { [weak self] in
      self?.pumpOnce()
    }
    pumpTimer = timer
    timer.resume()
  }

  private func pumpOnce() {
    if stopped { return }
    if source == "relay" {
      guard let log = WWNRelay.sharedRelay.consoleLog(forMachineId: machineId),
            log.count > fed else { return }
      let delta = log.subdata(in: fed..<log.count)
      fed = log.count
      append(delta)
    }
  }

  private func startShell() {
    var masterFd: Int32 = -1
    var slaveFd: Int32 = -1
    var win = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
    var name = [CChar](repeating: 0, count: 128)
    guard openpty(&masterFd, &slaveFd, &name, nil, &win) == 0 else {
      append(Data("Native shell did not start.\n".utf8))
      return
    }
    var actions: posix_spawn_file_actions_t?
    var attr: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var pid: pid_t = 0
    let path = strdup("/bin/zsh")
    let arg = strdup("-l")
    var argv: [UnsafeMutablePointer<CChar>?] = [path, arg, nil]
    let rc: Int32 = name.withUnsafeBufferPointer { buf in
      posix_spawn_file_actions_addopen(&actions, 0, buf.baseAddress, O_RDWR, 0)
      posix_spawn_file_actions_adddup2(&actions, 0, 1)
      posix_spawn_file_actions_adddup2(&actions, 0, 2)
      posix_spawn_file_actions_addclose(&actions, masterFd)
      posix_spawn_file_actions_addclose(&actions, slaveFd)
      return posix_spawn(&pid, "/bin/zsh", &actions, &attr, &argv, environ)
    }
    free(path)
    free(arg)
    posix_spawn_file_actions_destroy(&actions)
    posix_spawnattr_destroy(&attr)
    close(slaveFd)
    guard rc == 0 else {
      close(masterFd)
      append(Data("Native shell did not start.\n".utf8))
      return
    }
    master = masterFd
    shellPid = pid
    let fd = masterFd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: pumpQueue)
    source.setEventHandler { [weak self] in
      var buf = [UInt8](repeating: 0, count: 4096)
      let n = read(fd, &buf, buf.count)
      if n > 0 {
        self?.append(Data(buf.prefix(n)))
      }
    }
    shellReader = source
    source.resume()
    if let surface {
      setWinsize(cols: surface.gridCols, rows: surface.gridRows)
    }
  }

  /// Shell keys land on the VT view. Log consoles stay read-only.
  private func focusShellKeys() {
    guard source == "shell", let window, let surface else { return }
    window.makeFirstResponder(surface)
  }

  private func writeMaster(_ data: Data) {
    let fd = master
    guard fd >= 0, !data.isEmpty else { return }
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var sent = 0
      while sent < raw.count {
        let n = write(fd, base.advanced(by: sent), raw.count - sent)
        if n > 0 {
          sent += n
          continue
        }
        if n < 0, errno == EINTR {
          continue
        }
        break
      }
    }
  }

  private func setWinsize(cols: UInt32, rows: UInt32) {
    let fd = master
    guard fd >= 0 else { return }
    var win = winsize(
      ws_row: UInt16(min(rows, UInt32(UInt16.max))),
      ws_col: UInt16(min(cols, UInt32(UInt16.max))),
      ws_xpixel: 0,
      ws_ypixel: 0
    )
    _ = ioctl(fd, TIOCSWINSZ, &win)
  }

  private func append(_ data: Data) {
    if stopped || data.isEmpty { return }
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in self?.append(data) }
      return
    }
    guard let surface else { return }
    surface.feed(data)
  }
}
#endif
