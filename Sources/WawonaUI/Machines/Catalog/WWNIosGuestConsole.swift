#if os(iOS) || os(visionOS)
import Combine
import SwiftUI
import UIKit

/// Styled lines from `wwn_term_export`. Face: bundled DejaVuSansM Nerd Font Mono.
struct WawonaTerminalSpan: Identifiable {
  let id: Int
  let text: String
  let fg: UInt32
  let bg: UInt32
  let bold: Bool
  let italic: Bool
  let underline: Bool
}

struct WawonaTerminalLine: Identifiable {
  let id: Int
  let spans: [WawonaTerminalSpan]
}

final class WawonaTerminalModel: ObservableObject {
  @Published var lines: [WawonaTerminalLine] = []

  func applySnapshot(_ data: Data) {
    let next = WawonaTerminalSnapshot.lines(from: data)
    if Thread.isMainThread {
      lines = next
    } else {
      DispatchQueue.main.async { [weak self] in self?.lines = next }
    }
  }
}

enum WawonaTerminalSnapshot {
  static func lines(from data: Data) -> [WawonaTerminalLine] {
    if data.count < 4 { return [] }
    var offset = 0
    let lineCount = Int(readU32(data, &offset))
    var lines: [WawonaTerminalLine] = []
    lines.reserveCapacity(lineCount)
    for lineIndex in 0..<lineCount {
      if offset + 4 > data.count { break }
      let cells = Int(readU32(data, &offset))
      var pieces: [(UInt32, UInt32, UInt32, UInt32)] = []
      pieces.reserveCapacity(cells)
      for _ in 0..<cells {
        if offset + 16 > data.count { break }
        let cp = readU32(data, &offset)
        let fg = readU32(data, &offset)
        let bg = readU32(data, &offset)
        let attrs = readU32(data, &offset)
        pieces.append((cp, fg, bg, attrs))
      }
      var end = pieces.count
      while end > 0 {
        let cell = pieces[end - 1]
        if (cell.0 == 0 || cell.0 == 32) && cell.2 == 0 {
          end -= 1
        } else {
          break
        }
      }
      var spans: [WawonaTerminalSpan] = []
      var text = ""
      var style: (UInt32, UInt32, UInt32)?
      var spanID = 0
      for index in 0..<end {
        let cell = pieces[index]
        let key = (cell.1, cell.2, cell.3)
        let changed =
          style.map { $0.0 != key.0 || $0.1 != key.1 || $0.2 != key.2 } ?? true
        if changed {
          if !text.isEmpty, let style {
            spans.append(makeSpan(id: spanID, text: text, style: style))
            spanID += 1
            text = ""
          }
          style = key
        }
        let cp = cell.0 == 0 ? 32 : cell.0
        if let scalar = Unicode.Scalar(cp) {
          text.append(Character(scalar))
        }
      }
      if !text.isEmpty, let style {
        spans.append(makeSpan(id: spanID, text: text, style: style))
      }
      lines.append(WawonaTerminalLine(id: lineIndex, spans: spans))
    }
    return lines
  }

  private static func makeSpan(id: Int, text: String, style: (UInt32, UInt32, UInt32))
    -> WawonaTerminalSpan
  {
    WawonaTerminalSpan(
      id: id, text: text, fg: style.0, bg: style.1,
      bold: style.2 & 1 != 0, italic: style.2 & 4 != 0, underline: style.2 & 8 != 0
    )
  }

  private static func readU32(_ data: Data, _ offset: inout Int) -> UInt32 {
    let b0 = UInt32(data[offset])
    let b1 = UInt32(data[offset + 1])
    let b2 = UInt32(data[offset + 2])
    let b3 = UInt32(data[offset + 3])
    offset += 4
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  }
}

struct WawonaTerminalView: View {
  @ObservedObject var model: WawonaTerminalModel

  var body: some View {
    // ScrollViewReader via Dave DeLong namespace (`WawonaBackport`). Never bare
    // ScrollViewReader at the call site (iOS 13 floor).
    WawonaBackport<Any>.scrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(model.lines) { line in
            lineText(line)
              .frame(maxWidth: .infinity, alignment: .leading)
              .id(line.id)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
      }
      .background(Color.black)
      .onAppear { scrollTerminalToEnd(proxy) }
      .backport.onChange(of: model.lines.count) { _ in
        scrollTerminalToEnd(proxy)
      }
    }
  }

  private func scrollTerminalToEnd(_ proxy: WawonaScrollViewProxy) {
    guard let last = model.lines.last?.id else { return }
    DispatchQueue.main.async {
      proxy.scrollTo(last, anchor: .bottom)
    }
  }

  private func lineText(_ line: WawonaTerminalLine) -> some View {
    let body = line.spans.reduce(Text("")) { acc, span in
      acc + spanText(span)
    }
    return (line.spans.isEmpty ? Text(" ") : body)
      .font(.custom("DejaVuSansM Nerd Font Mono", size: 13))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: true)
      .frame(minHeight: 16, alignment: .leading)
  }

  private func spanText(_ span: WawonaTerminalSpan) -> Text {
    var text = Text(span.text).foregroundColor(rgb(span.fg))
    if span.bold { text = text.bold() }
    if span.italic { text = text.italic() }
    if span.underline { text = text.underline() }
    return text
  }

  private func rgb(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}

/// iOS / visionOS host for Guest console. Shell source runs in-process zsh
/// via `IosShellSession` (not a stub splash).
@MainActor
final class WWNIosGuestConsole: ObservableObject {
  static let shared = WWNIosGuestConsole()

  @Published var isPresented = false
  @Published var title = "Guest console"
  @Published var logText = ""
  @Published var inputLine = ""
  @Published var statusMessage = ""

  let termModel = WawonaTerminalModel()

  private var machineId = ""
  private var source = "relay"
  private var fed = 0
  private var pumpTimer: Timer?
  private var observer: NSObjectProtocol?
  private var launchLogObserver: NSObjectProtocol?
  private var started = false
  private var shell: IosShellSession?
  private var logTerm: IosLogTermSession?

  var isShell: Bool { source == "shell" }

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
    if isPresented, self.machineId == machineId, self.source == source {
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
    logText = ""
    termModel.lines = []
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

  func dismiss(machineId: String) {
    if !self.machineId.isEmpty, !machineId.isEmpty, machineId != self.machineId {
      return
    }
    stopPump()
    stopShell()
    stopLogTerm()
    isPresented = false
    self.machineId = ""
    source = "relay"
    fed = 0
    inputLine = ""
    statusMessage = ""
    logText = ""
  }

  /// Done = Focus: park Terminal, reveal mounted Wayland / Metal client.
  func userDismiss() {
    let mid = machineId
    dismiss(machineId: mid)
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
    logText += chunk
    logTerm?.feed(chunk)
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
      shell?.write(Data(text.utf8))
    } else {
      appendLog(text)
    }
  }

  func injectTerminalData(_ data: Data) {
    guard !data.isEmpty else { return }
    if isShell {
      shell?.write(data)
    } else if let text = String(data: data, encoding: .utf8) {
      appendLog(text)
    }
  }

  private func startShell() {
    let session = IosShellSession()
    session.onScreen = { [weak self] data in
      self?.termModel.applySnapshot(data)
    }
    session.onFailure = { [weak self] message in
      self?.statusMessage = message
      self?.appendLog(message + "\n")
    }
    shell = session
    session.start(cols: 80, rows: 28)
  }

  private func stopShell() {
    shell?.stop()
    shell = nil
  }

  private func startLogTerm() {
    stopLogTerm()
    let session = IosLogTermSession()
    session.onScreen = { [weak self] data in
      self?.termModel.applySnapshot(data)
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

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        WawonaTerminalView(model: console.termModel)
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
          onDismissKeyboard: {},
          autoFocus: true
        )
        .frame(width: 1, height: 1)
        .accessibility(identifier: "wwn.guestConsole.send")
        #elseif os(visionOS)
        if console.isShell {
          HStack(spacing: 8) {
            TextField("Type here", text: $console.inputLine, onCommit: {
              console.submitInput()
            })
            .font(.custom("DejaVuSansM Nerd Font Mono", size: 14))
            .padding(8)
            .background(Color(white: 0.12))
            .cornerRadius(6)
            Button("Send") { console.submitInput() }
              .accessibility(identifier: "wwn.guestConsole.send")
            Button("^C") { console.sendControl(0x03) }
              .accessibility(identifier: "wwn.guestConsole.ctrlC")
          }
          .padding(8)
          .background(Color.black)
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
        EmptyView()
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
  }
}
#endif
