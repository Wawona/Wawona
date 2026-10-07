#if os(macOS)
import AppKit

/// AppKit host for the guest console. Relay boot, SSH, and a native
/// shell show here until a Wayland client is on screen. The surface
/// parses ANSI and draws DejaVuSansM Nerd Font Mono with Metal.
@objc final class WWNMacGuestConsole: NSObject, NSWindowDelegate {
  @objc static let shared = WWNMacGuestConsole()

  private var window: NSWindow?
  private var surface: WWNTermSurface?
  private let pumpQueue = DispatchQueue(label: "com.aspauldingcode.wawona.mac-guest-console")
  private var pumpTimer: DispatchSourceTimer?
  private var fed = 0
  private var machineId = ""
  private var source = "relay"
  private var shell: Process?
  private var shellInput: Pipe?
  private var stopped = false

  func present(machineId: String, source: String) {
    guard !machineId.isEmpty else { return }
    if let existing = window, self.machineId == machineId {
      existing.makeKeyAndOrderFront(nil)
      return
    }
    dismiss(machineId: self.machineId)
    self.machineId = machineId
    self.source = source
    self.fed = 0
    self.stopped = false

    let surface = WWNTermSurface(frame: NSRect(x: 0, y: 0, width: 780, height: 480))
    surface.onReply = { [weak self] data in
      self?.shellInput?.fileHandleForWriting.write(data)
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
    window.title = "Guest console"
    window.contentView = surface
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window

    if source == "shell" {
      startShell()
    } else {
      let banner = source == "ssh" ? "SSH session starting.\n" : "Guest console\n"
      surface.feed(Data(banner.utf8))
    }
    startPump()
  }

  func dismiss(machineId: String) {
    if !self.machineId.isEmpty, machineId != self.machineId { return }
    stopped = true
    pumpTimer?.cancel()
    pumpTimer = nil
    shell?.terminate()
    shell = nil
    shellInput = nil
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
    if stopped || source != "relay" { return }
    guard let log = WWNRelay.sharedRelay.consoleLog(forMachineId: machineId),
          log.count > fed else { return }
    let delta = log.subdata(in: fed..<log.count)
    fed = log.count
    append(delta)
  }

  private func startShell() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l"]
    let output = Pipe()
    let input = Pipe()
    process.standardOutput = output
    process.standardError = output
    process.standardInput = input
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if !data.isEmpty { self?.append(data) }
    }
    do {
      try process.run()
      shell = process
      shellInput = input
    } catch {
      append(Data("Native shell did not start.\n".utf8))
    }
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
