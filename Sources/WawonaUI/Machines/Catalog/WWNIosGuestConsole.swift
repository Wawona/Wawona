#if os(iOS) || os(tvOS) || os(visionOS)
import Combine
import SwiftUI
import UIKit

/// iOS / visionOS host for Guest console. Shell source runs in-process zsh
/// via `IosShellSession` (not a stub splash).
@MainActor
final class WWNIosGuestConsole: ObservableObject {
  static let shared = WWNIosGuestConsole()

  @Published var isPresented = false
  /// New Window on iPad / visionOS. The main window must not also show the tab.
  @Published var windowed = false
  /// Set by Start before the present notification. Cleared in `present`.
  static var openNextInWindow = false
  @Published var title = "Guest console"
  @Published var inputLine = ""
  @Published var statusMessage = ""

  let termModel = WawonaTerminalModel()
  @Published var screenRows: UInt32 = 28

  private var machineId = ""
  private var source = "relay"
  private var fed = 0
  private var pumpTimer: Timer?
  private var observer: NSObjectProtocol?
  private var launchLogObserver: NSObjectProtocol?
  private var started = false
  private var shell: IosShellSession?
  private var logTerm: IosLogTermSession?
  private var keyRepeatTimer: Timer?
  private var keyRepeatBytes: [UInt8]?
  private var keyRepeatTicks = 0

  var isShell: Bool { source == "shell" }

  /// Hide Terminal chrome while keeping its shell or log session alive.
  func parkForCompositor() {
    guard isPresented else { return }
    isPresented = false
    NSLog("WWNIosGuestConsole: parked Terminal (session kept alive) mid=%@", machineId)
  }

  func startObservingIfNeeded() {
    guard !started else { return }
    started = true
    observer = NotificationCenter.default.addObserver(
      forName: Notification.Name("WWNRelayGuestConsoleNeededNotification"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let console = self else { return }
      let info = note.userInfo ?? [:]
      let mid = info["machineId"] as? String ?? ""
      let src = info["source"] as? String ?? "relay"
      if src == "close" {
        console.dismiss(machineId: mid)
      } else {
        console.present(machineId: mid, source: src)
      }
    }
    launchLogObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("WWNClientLaunchLogNotification"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let console = self, console.isPresented else { return }
      guard console.source == "client" || console.source == "relay" else { return }
      if let line = note.userInfo?["line"] as? String, !line.isEmpty {
        console.appendLog(line)
      }
    }
  }

  func present(machineId: String, source: String) {
    guard !machineId.isEmpty else { return }
    if self.machineId == machineId, self.source == source {
      if !isPresented {
        windowed = Self.openNextInWindow
        Self.openNextInWindow = false
        isPresented = true
      }
      return
    }
    stopPump()
    stopShell()
    stopLogTerm()
    self.machineId = machineId
    self.source = source
    fed = 0
    inputLine = ""
    statusMessage = ""
    termModel.reset()
    windowed = Self.openNextInWindow
    Self.openNextInWindow = false
    title = "Wawona Terminal"
    switch source {
    case "shell":
      startShell()
    case "ssh":
      startLogTerm()
      appendLog("SSH session starting.\n")
    case "client":
      startLogTerm()
      appendLog(clientStartBanner(machineId: machineId))
    default:
      startLogTerm()
      appendLog("Wawona Terminal\n")
    }
    isPresented = true
    if source == "relay" || source == "client" {
      startPump()
    }
  }

  func fitTerminal(to size: CGSize) {
    guard size.width > 1, size.height > 1 else { return }
    let cellW = WawonaTerminalFonts.cellWidth
    let cellH = WawonaTerminalFonts.rowHeight
    let pixelCols = UInt32(min(512, max(20, Int((size.width - 16) / cellW))))
    let rows = UInt32(min(256, max(8, Int((size.height - 16) / cellH))))
    screenRows = rows
    let pxW = UInt32(max(1, cellW.rounded()))
    let pxH = UInt32(max(1, cellH.rounded()))
    // Native shell: follow the visible grid.
    shell?.resize(cols: pixelCols, rows: rows, cellW: pxW, cellH: pxH)
    // Guest serial / systemd / ncurses: floor at 80 columns so in-place
    // `\r` / ESC M / CSI K rewrites stay one logical line on phone width.
    // wrap_cont still heals narrower grids; 80 matches classic VT/serial.
    let logCols = max(pixelCols, 80)
    logTerm?.resize(cols: logCols, rows: rows, cellW: pxW, cellH: pxH)
  }

  func dismiss(machineId: String) {
    if !self.machineId.isEmpty, !machineId.isEmpty, machineId != self.machineId {
      return
    }
    stopPump()
    stopShell()
    stopLogTerm()
    isPresented = false
    windowed = false
    self.machineId = ""
    source = "relay"
    fed = 0
    inputLine = ""
    statusMessage = ""
  }

  /// Scene activation failed. Show the terminal in the current window.
  func fallBackToTab() {
    windowed = false
    if !machineId.isEmpty {
      isPresented = true
    }
  }

  /// Done = Focus: park Terminal, reveal mounted Wayland / Metal client.
  func userDismiss() {
    let mid = machineId
    let wasWindow = windowed
    dismiss(machineId: mid)
    #if os(iOS) || os(visionOS)
    if wasWindow {
      WWNSessionWindowPresenter.closeTerminalWindow()
    }
    #endif
    guard !mid.isEmpty else { return }
    WWNMachineProfileStore.setActiveMachineId(mid)
    WWNMainWindowRouter.shared.showSessionSurface()
    NotificationCenter.default.post(
      name: .WWNClientFocusRequested,
      object: nil,
      userInfo: ["machineId": mid]
    )
  }

  private func appendLog(_ chunk: String) {
    guard !chunk.isEmpty else { return }
    if isShell {
      shell?.feedLocal(Data(chunk.utf8))
    } else {
      logTerm?.feed(chunk)
    }
  }

  func pointer(button: UInt32, col: UInt32, row: UInt32, pressed: Bool, motion: Bool) {
    guard isShell else { return }
    shell?.pointer(button: UInt8(truncatingIfNeeded: button), col: col, row: row, pressed: pressed, motion: motion)
  }

  func clearScreen() {
    let erase = Data([0x1B, 0x5B, 0x33, 0x4A])
    if isShell {
      shell?.feedLocal(erase)
    } else {
      logTerm?.feed(erase)
    }
  }

  func submitInput() {
    guard isShell else { return }
    var payload = inputLine
    if !payload.hasSuffix("\n") {
      payload += "\n"
    }
    shell?.write(Data(payload.utf8))
    inputLine = ""
  }

  func sendControl(_ byte: UInt8) {
    guard isShell else { return }
    shell?.write(Data([byte]))
  }

  /// Toolbar Keys / soft keyboard → PTY (shell) or log echo (relay Terminal).
  func injectTerminalText(_ text: String) {
    guard !text.isEmpty else { return }
    if isShell {
      if text.utf8.count > 1, text.contains("\n") || text.contains("\r") {
        shell?.writePaste(Data(text.utf8))
      } else {
        var data = Data(text.utf8)
        #if os(iOS) || os(tvOS) || os(visionOS)
        data = WWNTerminalCursorMode.mapArrow(data)
        #endif
        shell?.write(data)
      }
    } else {
      appendLog(text)
    }
  }

  func injectTerminalPaste(_ text: String) {
    guard !text.isEmpty else { return }
    if isShell {
      shell?.writePaste(Data(text.utf8))
    } else {
      appendLog(text)
    }
  }

  func armKeyRepeat(_ bytes: [UInt8]) {
    keyRepeatTimer?.invalidate()
    keyRepeatBytes = bytes
    keyRepeatTicks = 0
    keyRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
      guard let self, let bytes = self.keyRepeatBytes else { timer.invalidate(); return }
      self.keyRepeatTicks += 1
      guard self.keyRepeatTicks >= 8 else { return }
      self.injectTerminalData(Data(bytes))
    }
  }

  func cancelKeyRepeat() {
    keyRepeatBytes = nil
    keyRepeatTimer?.invalidate()
    keyRepeatTimer = nil
  }

  func injectTerminalData(_ data: Data) {
    guard !data.isEmpty else { return }
    #if os(iOS) || os(tvOS) || os(visionOS)
    let bytes = isShell ? WWNTerminalCursorMode.mapArrow(data) : data
    #else
    let bytes = data
    #endif
    if isShell {
      shell?.write(bytes)
    } else if let text = String(data: data, encoding: .utf8) {
      appendLog(text)
    }
  }

  private func startShell() {
    let session = IosShellSession()
    session.onScreen = { [weak self] data in
      self?.termModel.applyLines(data)
    }
    session.onPictures = { [weak self] data in
      self?.termModel.applyPictures(data)
    }
    session.onCells = { [weak self] cells, cols, rows in
      self?.termModel.applyCells(cells, cols: Int(cols), rows: Int(rows))
    }
    session.onFailure = { [weak self] message in
      self?.statusMessage = message
      self?.appendLog(message + "\n")
    }
    shell = session
    session.start(cols: 80, rows: 28)
  }

  private func stopShell() {
    cancelKeyRepeat()
    shell?.stop()
    shell = nil
  }

  private func startLogTerm() {
    stopLogTerm()
    let session = IosLogTermSession()
    session.onScreen = { [weak self] data in
      self?.termModel.applyLines(data)
    }
    session.onPictures = { [weak self] data in
      self?.termModel.applyPictures(data)
    }
    session.onCells = { [weak self] cells, cols, rows in
      self?.termModel.applyCells(cells, cols: Int(cols), rows: Int(rows))
    }
    logTerm = session
    session.start(cols: 80, rows: 28)
  }

  private func stopLogTerm() {
    logTerm?.stop()
    logTerm = nil
  }

  private func startPump() {
    stopPump()
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let console = self else { return }
      if Thread.isMainThread {
        console.pumpOnce()
      } else {
        DispatchQueue.main.async { console.pumpOnce() }
      }
    }
    pumpTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopPump() {
    pumpTimer?.invalidate()
    pumpTimer = nil
  }

  private func pumpOnce() {
    guard source == "relay" || source == "client", !machineId.isEmpty else { return }
    if let log = WWNRelay.sharedRelay.consoleLog(forMachineId: machineId),
       log.count > fed
    {
      let delta = log.subdata(in: fed..<log.count)
      fed = log.count
      if let chunk = String(data: delta, encoding: .utf8), !chunk.isEmpty {
        appendLog(chunk)
      }
    }
  }

  private func clientStartBanner(machineId: String) -> String {
    guard let profile = WWNMachineProfileStore.profile(byId: machineId) else {
      return "Wawona Terminal\n"
    }
    let prefs = WWNPreferencesManager.sharedManager()
    let kind = WWNNativeShellConfiguration.kind(for: profile)
    if kind == kWWNNativeShellKindWaypipe
      || profile.type == kWWNMachineTypeSSHWaypipe
    {
      let preview = WWNWaypipeRunner.sharedRunner().generateWaypipePreviewString(prefs)
      return "$ \(preview)\n# Done focuses the compositor.\n"
    }
    let client = WWNMachineSessionBridge.nativeClientId(forProfile: profile) ?? "client"
    let display = WWNCompositorBridge.sharedBridge.socketName()
    return """
    $ wwn-exec \(client)
    WAYLAND_DISPLAY=\(display.isEmpty ? "wayland-0" : display)
    # Done focuses the compositor.

    """
  }
}

struct WWNIosGuestConsoleSheet: View {
  @ObservedObject var console: WWNIosGuestConsole
  @State private var keyFocus = 0

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        WawonaTerminalView(model: console.termModel, screenRows: console.screenRows) { col, row, button, pressed, motion in
          console.pointer(button: button, col: col, row: row, pressed: pressed, motion: motion)
          if !pressed { keyFocus += 1 }
        }
          .background(
            GeometryReader { geo in
              Color.clear.preference(key: WawonaTerminalViewportKey.self, value: geo.size)
            }
          )
          .onPreferenceChange(WawonaTerminalViewportKey.self) { size in
            console.fitTerminal(to: size)
          }
        if !console.statusMessage.isEmpty {
          Text(console.statusMessage)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        #if os(iOS)
        // Toolbar Keys owns soft-keyboard chrome (Esc/Tab/arrows/modifiers).
        // Host is near-invisible; accessory draws above the system keyboard.
        WWNTerminalToolbarHost(
          isShell: console.isShell,
          onInjectData: { console.injectTerminalData($0) },
          onInjectText: { console.injectTerminalText($0) },
          onPaste: { console.injectTerminalPaste($0) },
          onDismissKeyboard: {},
          autoFocus: true,
          focusTick: keyFocus,
          onKeyRepeat: { console.armKeyRepeat($0) },
          onKeyUp: { console.cancelKeyRepeat() }
        )
        .frame(width: 1, height: 1)
        .accessibility(identifier: "wwn.guestConsole.send")
        #elseif os(tvOS) || os(visionOS)
        if console.isShell {
          WWNTerminalKeyHost(
            onInjectData: { console.injectTerminalData($0) },
            onInjectText: { console.injectTerminalText($0) },
            autoFocus: true,
            focusTick: keyFocus
          )
          .frame(width: 1, height: 1)
          .accessibility(identifier: "wwn.guestConsole.send")
          #if os(visionOS)
          HStack {
            Button("^C") { console.sendControl(0x03) }
              .accessibility(identifier: "wwn.guestConsole.ctrlC")
          }
          .padding(8)
          .background(Color.black)
          #endif
        }
        #endif
      }
      .background(Color.black)
      .accessibility(identifier: WWNA11y.terminalRoot)
      .backport.navigationTitle(console.title, inline: true)
      .backport.navigationActions {
        Button("Done") { console.userDismiss() }
          .accessibility(identifier: WWNA11y.terminalDone)
      } trailing: {
        Button("Clear") { console.clearScreen() }
          .accessibility(identifier: "wwn.terminal.clear")
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
      guard console.isShell, let bytes = WWNTerminalCursorMode.focusReport(false) else { return }
      console.injectTerminalData(bytes)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      guard console.isShell, let bytes = WWNTerminalCursorMode.focusReport(true) else { return }
      console.injectTerminalData(bytes)
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
  }
}
#endif
