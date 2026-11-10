#if os(iOS) || os(tvOS) || os(visionOS)
import Combine
import notify
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
  private var labDismissToken: Int32 = 0
  private var shell: IosShellSession?
  private var logTerm: IosLogTermSession?
  private var keyRepeatTimer: Timer?
  private var keyRepeatBytes: [UInt8]?
  private var keyRepeatTicks = 0
  /// Soft-exit restart budget. Immediate crash-loop stops after 3.
  private var shellRestartCount = 0
  private var shellEndedAt: Date?
  /// Matches Rust `terminal_liveness::ENDED_NOTICE`.
  private static let sessionEndedNotice = "[session ended]"

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
      let info = note.userInfo ?? [:]
      let mid = info["machineId"] as? String ?? ""
      let src = info["source"] as? String ?? "relay"
      Task { @MainActor [weak self] in
        guard let console = self else { return }
        if src == "close" {
          // Stop already owns session teardown. Chrome only (no re-disconnect).
          console.dismissChrome(machineId: mid)
        } else {
          console.present(machineId: mid, source: src)
        }
      }
    }
    // Lab / simctl: `notifyutil -p com.aspauldingcode.wawona.lab-dismiss-terminal`
    // (visionOS AX often reports Done at window origin; hands/eyes still hit it).
    // Dual register: CF Darwin center (proven on vision/tv tips) + notify(3).
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      UnsafeRawPointer(bitPattern: 1),
      { _, _, _, _, _ in
        NSLog("WWNIosGuestConsole: lab-dismiss CFNotification fired")
        DispatchQueue.main.async {
          WWNIosGuestConsole.shared.userDismiss()
        }
      },
      "com.aspauldingcode.wawona.lab-dismiss-terminal" as CFString,
      nil,
      .deliverImmediately
    )
    var token: Int32 = 0
    let status = notify_register_dispatch(
      "com.aspauldingcode.wawona.lab-dismiss-terminal",
      &token,
      DispatchQueue.main
    ) { _ in
      NSLog("WWNIosGuestConsole: lab-dismiss notify fired")
      WWNIosGuestConsole.shared.userDismiss()
    }
    if status == NOTIFY_STATUS_OK {
      labDismissToken = token
      NSLog("WWNIosGuestConsole: lab-dismiss notify token=%d", token)
    } else {
      NSLog("WWNIosGuestConsole: lab-dismiss notify register failed status=%d", status)
    }
    launchLogObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("WWNClientLaunchLogNotification"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      let line = note.userInfo?["line"] as? String
      Task { @MainActor [weak self] in
        guard let console = self, console.isPresented else { return }
        guard console.source == "client" || console.source == "relay" else { return }
        if let line, !line.isEmpty {
          console.appendLog(line)
        }
      }
    }
  }

  func present(machineId: String, source: String) {
    guard !machineId.isEmpty else { return }
    if self.machineId == machineId, self.source == source {
      if !isPresented {
        windowed = Self.resolveWindowed(source: source)
        Self.openNextInWindow = false
        isPresented = true
        presentTerminalSceneIfNeeded(source: source)
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
    shellRestartCount = 0
    shellEndedAt = nil
    termModel.reset()
    windowed = Self.resolveWindowed(source: source)
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
    // Shell / SSH Terminal must sit above Machines. If sessionSurfaceVisible
    // is true (AUTO_START mount + accidental Show), the ZStack hides this
    // sheet and the user only sees Machines / empty Metal.
    if source == "shell" || source == "ssh" {
      WWNMainWindowRouter.shared.hideSessionSurface()
      WWNMainWindowRouter.shared.showMachines()
    }
    // visionOS shell/ssh: dedicated Terminal scene so system close / Done
    // leave Machines alive. Overlay Exclusive swap stays for iPhone / tvOS
    // and for scene-activation fallback.
    isPresented = true
    presentTerminalSceneIfNeeded(source: source)
    if source == "relay" || source == "client" {
      startPump()
    }
    // Lab only: SIMCTL_CHILD_WWN_LAB_TYPE_TEXT='echo hi' (+ optional delay).
    // xrSimulator AX taps miss the floating window; prove PTY inject this way.
    if let labType = ProcessInfo.processInfo.environment["WWN_LAB_TYPE_TEXT"],
      !labType.isEmpty
    {
      let typeMs = Int(ProcessInfo.processInfo.environment["WWN_LAB_TYPE_AFTER_MS"] ?? "800") ?? 800
      let typeDelay = TimeInterval(max(0, typeMs)) / 1000.0
      DispatchQueue.main.asyncAfter(deadline: .now() + typeDelay) {
        let line = labType.hasSuffix("\n") ? labType : labType + "\n"
        NSLog("WWNIosGuestConsole: lab type inject n=%d", line.utf8.count)
        WWNIosGuestConsole.shared.injectTerminalText(line)
      }
    }
    // Lab only: SIMCTL_CHILD_WWN_LAB_DISMISS_AFTER_MS=2500. Product Done is
    // the in-window UIKit button / Escape / window disconnect → userDismiss.
    if let raw = ProcessInfo.processInfo.environment["WWN_LAB_DISMISS_AFTER_MS"],
      let ms = Int(raw), ms > 0
    {
      let delay = TimeInterval(ms) / 1000.0
      NSLog("WWNIosGuestConsole: lab auto-dismiss in %.2fs", delay)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        NSLog("WWNIosGuestConsole: lab auto-dismiss firing")
        WWNIosGuestConsole.shared.userDismiss()
      }
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
    // Drop chrome before PTY join so Done never looks stuck behind
    // `wwn_pty_ios_stop_shell_session` (tvOS 10-foot + soft-exit).
    isPresented = false
    windowed = false
    stopPump()
    stopShell()
    stopLogTerm()
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

  /// visionOS / iPad New Window: Terminal owns its own scene so closing it
  /// does not terminate the Machines window.
  private static func resolveWindowed(source: String) -> Bool {
    if openNextInWindow { return true }
    #if os(visionOS)
    return source == "shell" || source == "ssh"
    #else
    return false
    #endif
  }

  private func presentTerminalSceneIfNeeded(source: String) {
    #if os(iOS) || os(visionOS)
    guard windowed else { return }
    _ = source
    WWNSessionWindowPresenter.presentTerminalWindow()
    #else
    _ = source
    #endif
  }

  /// Stop / scene close: tear down Terminal chrome only. Session disconnect
  /// already ran (or is running) in `WWNMachinesViewModel.disconnect`.
  func dismissChrome(machineId mid: String) {
    let wasWindow = windowed
    let shellOnly = isShell || source == "ssh"
    let nested = WWNNestedClientTabStore.shared.nestedCount
    dismiss(machineId: mid.isEmpty ? machineId : mid)
    isPresented = false
    windowed = false
    #if os(iOS) || os(visionOS)
    if wasWindow {
      WWNSessionWindowPresenter.closeTerminalWindow()
    }
    #endif
    if shellOnly || nested == 0 {
      WWNMainWindowRouter.shared.hideSessionSurface()
      WWNMainWindowRouter.shared.showMachines()
      NSLog(
        "WWNIosGuestConsole: Stop → Machines mid=%@ shell=%d nested=%d",
        mid, shellOnly ? 1 : 0, nested
      )
      return
    }
    guard !mid.isEmpty else {
      WWNMainWindowRouter.shared.hideSessionSurface()
      WWNMainWindowRouter.shared.showMachines()
      return
    }
    WWNMainWindowRouter.shared.showSessionSurface()
    NotificationCenter.default.post(
      name: .WWNClientFocusRequested,
      object: nil,
      userInfo: ["machineId": mid]
    )
  }

  /// Done leaves Terminal chrome and stops the Machines session (Stop parity).
  /// Shell / SSH / Terminal-only Native Shell return to Machines. Never reveal
  /// empty CompositorBridge (blank Metal on visionOS / tvOS / iPad).
  func userDismiss() {
    NSLog("WWNIosGuestConsole: userDismiss begin mid=%@", machineId)
    // Drop visionOS / iOS soft IME so it cannot keep covering Done.
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
    let mid = machineId
    // Hide Terminal overlay first, then join PTY / disconnect.
    dismissChrome(machineId: mid)
    if !mid.isEmpty {
      WWNMachineProfileStore.setActiveMachineId(mid)
    }
    // Done = Stop: tear down PTY / native session, not chrome alone.
    if !mid.isEmpty,
      let profile = WWNMachineProfileStore.profile(byId: mid),
      WWNMachinesViewModel.shared.status(for: mid) != .disconnected
    {
      WWNMachinesViewModel.shared.disconnect(profile)
    }
    NSLog("WWNIosGuestConsole: Done → Machines mid=%@", mid)
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

  func injectTerminalPaste(_ text: String, submit: Bool = false) {
    guard !text.isEmpty else { return }
    if isShell {
      shell?.writePaste(Data(text.utf8), trailer: submit ? Data([0x0d]) : Data())
    } else {
      appendLog(submit ? text + "\n" : text)
    }
  }

  func armKeyRepeat(_ bytes: [UInt8]) {
    keyRepeatTimer?.invalidate()
    keyRepeatBytes = bytes
    keyRepeatTicks = 0
    keyRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
      Task { @MainActor [weak self] in
        guard let self else {
          timer.invalidate()
          return
        }
        guard let bytes = self.keyRepeatBytes else {
          timer.invalidate()
          return
        }
        self.keyRepeatTicks += 1
        guard self.keyRepeatTicks >= 8 else { return }
        self.injectTerminalData(Data(bytes))
      }
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
      // Hard start failure only. Never the old "Shell exited." string.
      self?.statusMessage = message
      self?.appendLog(message + "\n")
    }
    session.onEnded = { [weak self] in
      self?.handleShellEnded()
    }
    shell = session
    session.start(cols: 80, rows: 28)
  }

  /// Soft EOF (`exit`, soft-exit, hangup). Restart a live shell; crash-loop
  /// paints `[session ended]` once instead of a useless "Shell exited." toast.
  private func handleShellEnded() {
    guard isPresented, isShell else {
      shell = nil
      return
    }
    let now = Date()
    if let last = shellEndedAt, now.timeIntervalSince(last) < 2.0 {
      shellRestartCount += 1
    } else {
      shellRestartCount = 0
    }
    shellEndedAt = now
    NSLog(
      "WWNIosGuestConsole: shell ended mid=%@ restartCount=%d",
      machineId, shellRestartCount
    )
    cancelKeyRepeat()
    shell = nil
    if shellRestartCount >= 3 {
      statusMessage = Self.sessionEndedNotice
      appendLog("\n\(Self.sessionEndedNotice)\n")
      return
    }
    statusMessage = ""
    startShell()
  }

  private func stopShell() {
    cancelKeyRepeat()
    guard let session = shell else { return }
    shell = nil
    session.onEnded = nil
    session.onFailure = nil
    // Done / Stop: never pthread_join on the UI thread (tvOS lockhistfile hang).
    session.stop(joinOffMain: true)
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
      Task { @MainActor [weak self] in
        self?.pumpOnce()
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
  #if os(tvOS)
  @FocusState private var doneFocused: Bool
  #endif

  var body: some View {
    #if os(visionOS)
    // No NavigationView: its 92pt bar reports the same 2D frame as a top
    // ornament Done (hittable=false / covered). In-window chrome + Escape
    // are the exit surfaces; host swaps Machines out while presented.
    terminalBody
      .background(Color.black)
      .preferredColorScheme(.dark)
      .background(WWNTerminalEscapeDismissHost(onEscape: { console.userDismiss() }))
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
        guard console.isShell, let bytes = WWNTerminalCursorMode.focusReport(false) else { return }
        console.injectTerminalData(bytes)
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
        guard console.isShell, let bytes = WWNTerminalCursorMode.focusReport(true) else { return }
        console.injectTerminalData(bytes)
      }
    #else
    NavigationView {
      terminalBody
        .background(Color.black)
        .backport.navigationTitle(console.title, inline: true)
        #if os(iOS)
        .backport.navigationActions {
          Button("Done") { console.userDismiss() }
            .accessibility(identifier: WWNA11y.terminalDone)
        } trailing: {
          Button("Clear") { console.clearScreen() }
            .accessibility(identifier: "wwn.terminal.clear")
        }
        #endif
    }
    #if os(tvOS)
    // Menu / Escape leave Terminal when UIKit Done is off-focus or clipped.
    .background(WWNTerminalEscapeDismissHost(onEscape: { console.userDismiss() }))
    .onReceive(NotificationCenter.default.publisher(for: .WWNTvRemoteMenuBeganNotification)) { _ in
      console.userDismiss()
    }
    .onReceive(NotificationCenter.default.publisher(for: .WWNTvRemoteShakeNotification)) { _ in
      guard WWNMachineProfileStore.resolvedShakeToCloseActive() else { return }
      console.userDismiss()
    }
    #endif
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
    #endif
  }

  @ViewBuilder
  private var terminalBody: some View {
    VStack(spacing: 0) {
      #if os(tvOS) || os(visionOS)
      // Real layout row (not safeAreaInset / ornament). UIViewRepresentable
      // grid still hit-tests under insets; top ornament shares the nav bar's
      // 2D frame on visionOS and stays covered.
      visionTerminalChrome
      #endif
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
        .accessibility(identifier: WWNA11y.terminalRoot)
      if !console.statusMessage.isEmpty {
        Text(console.statusMessage)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.orange)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 4)
      }
      #if os(iOS)
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
      // visionOS: do NOT auto-focus on appear. Soft IME covers exit chrome.
      // Tap the grid (focusTick) when the user wants to type.
      if console.isShell {
        WWNTerminalKeyHost(
          onInjectData: { console.injectTerminalData($0) },
          onInjectText: { console.injectTerminalText($0) },
          autoFocus: false,
          focusTick: keyFocus
        )
        .frame(width: 1, height: 1)
        .accessibility(hidden: true)
      }
      #endif
    }
  }

  #if os(tvOS) || os(visionOS)
  /// Exit / Clear / ^C as a layout sibling above the grid (not an inset).
  @ViewBuilder
  private var visionTerminalChrome: some View {
    #if os(tvOS)
    // 10-foot: SwiftUI focusable Buttons. Tiny UIKit 72×36 pills clipped to
    // unreadable glyphs and never took Menu / Focus Engine correctly.
    HStack(spacing: 28) {
      Button {
        NSLog("WWNIosGuestConsole: chrome Done tvOS shell=%d", console.isShell ? 1 : 0)
        if console.isShell {
          console.userDismiss()
        } else {
          // Match launch banner: Done focuses compositor (keep session alive).
          console.parkForCompositor()
          WWNMainWindowRouter.shared.showSessionSurface()
        }
      } label: {
        Text("Done")
          .font(.headline.weight(.semibold))
          .frame(minWidth: 160, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .tint(.accentColor)
      .focused($doneFocused)
      .wwnA11y(WWNA11y.terminalDone, label: "Done")
      .onAppear { doneFocused = true }

      Button {
        console.clearScreen()
      } label: {
        Text("Clear")
          .font(.headline.weight(.semibold))
          .frame(minWidth: 140, minHeight: 44)
      }
      .buttonStyle(.bordered)
      .wwnA11y("wwn.terminal.clear", label: "Clear")

      if console.isShell {
        Button {
          console.sendControl(0x03)
          // Soft ^C must not steal focus forever; Done stays the escape.
          doneFocused = true
        } label: {
          Text("^C")
            .font(.headline.weight(.semibold))
            .frame(minWidth: 100, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .wwnA11y("wwn.guestConsole.ctrlC", label: "Control C")

        WWNTvTerminalKeyboardField(
          onInjectData: { console.injectTerminalData($0) },
          onPasteLine: { console.injectTerminalPaste($0, submit: true) }
        )
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.black.opacity(0.92))
    .zIndex(10)
    #else
    HStack(spacing: 16) {
      // visionOS: UIKit Done implements accessibilityActivate (gaze / AX)
      // after resigning soft IME. SwiftUI Button actions were a no-op under
      // xrSimulator coordinate taps; Escape host is the keyboard path.
      WWNTerminalDoneButton(
        title: "Done",
        accessibilityId: WWNA11y.terminalDone
      ) {
        NSLog("WWNIosGuestConsole: chrome Done UIKit")
        console.userDismiss()
      }
      .frame(minWidth: 96, minHeight: 44)
      WWNTerminalDoneButton(
        title: "Clear",
        accessibilityId: "wwn.terminal.clear"
      ) {
        console.clearScreen()
      }
      .frame(minWidth: 96, minHeight: 44)
      if console.isShell {
        WWNTerminalDoneButton(
          title: "^C",
          accessibilityId: "wwn.guestConsole.ctrlC"
        ) {
          console.sendControl(0x03)
        }
        .frame(minWidth: 72, minHeight: 44)
      }
      Text(console.title)
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.leading, 8)
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.black.opacity(0.92))
    .zIndex(10)
    #endif
  }
  #endif
}

#endif
