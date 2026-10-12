#if os(iOS) || os(visionOS)
import Combine
import SwiftUI
import UIKit

/// iOS / visionOS host for Guest console. Relay boot logs, SSH, and Native
/// Shell Terminal Start post `WWNRelayGuestConsoleNeededNotification`; macOS
/// uses `WWNMacGuestConsole`. Shell source runs in-process zsh via
/// `IosShellSession` (not a stub splash).
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
  private var started = false
  private var shell: IosShellSession?

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
  }

  func present(machineId: String, source: String) {
    guard !machineId.isEmpty else { return }
    if isPresented, self.machineId == machineId, self.source == source {
      return
    }
    stopPump()
    stopShell()
    self.machineId = machineId
    self.source = source
    fed = 0
    inputLine = ""
    statusMessage = ""
    termModel.lines = []
    switch source {
    case "shell":
      title = "Wawona Terminal"
      logText = ""
      startShell()
    case "ssh":
      title = "SSH session"
      logText = "SSH session starting.\n"
    default:
      title = "Guest console"
      logText = "Guest console\n"
    }
    isPresented = true
    if source == "relay" {
      startPump()
    }
  }

  func dismiss(machineId: String) {
    if !self.machineId.isEmpty, !machineId.isEmpty, machineId != self.machineId {
      return
    }
    stopPump()
    stopShell()
    isPresented = false
    self.machineId = ""
    source = "relay"
    fed = 0
    inputLine = ""
    statusMessage = ""
  }

  func userDismiss() {
    dismiss(machineId: machineId)
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

  private func startShell() {
    let session = IosShellSession()
    session.onScreen = { [weak self] data in
      self?.termModel.applySnapshot(data)
    }
    session.onFailure = { [weak self] message in
      self?.statusMessage = message
      self?.logText = message + "\n"
    }
    shell = session
    session.start(cols: 80, rows: 28)
  }

  private func stopShell() {
    shell?.stop()
    shell = nil
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
    guard source == "relay", !machineId.isEmpty else { return }
    guard let log = WWNRelay.sharedRelay.consoleLog(forMachineId: machineId),
          log.count > fed
    else { return }
    let delta = log.subdata(in: fed..<log.count)
    fed = log.count
    if let chunk = String(data: delta, encoding: .utf8), !chunk.isEmpty {
      logText += chunk
    }
  }
}

struct WWNIosGuestConsoleSheet: View {
  @ObservedObject var console: WWNIosGuestConsole

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        if console.isShell {
          WawonaTerminalView(model: console.termModel)
          if !console.statusMessage.isEmpty {
            Text(console.statusMessage)
              .font(.system(.caption2, design: .monospaced))
              .foregroundColor(.orange)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
          }
          #if !os(tvOS)
          HStack(spacing: 8) {
            TextField("Type here", text: $console.inputLine, onCommit: {
              console.submitInput()
            })
            .font(.system(.body, design: .monospaced))
            #if os(iOS)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            #endif
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
          #endif
        } else {
          ScrollView {
            Text(console.logText.isEmpty ? " " : console.logText)
              .font(.system(.footnote, design: .monospaced))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
          }
          .background(Color.black)
        }
      }
      .background(Color.black)
      .backport.navigationTitle(console.title, inline: true)
      .backport.navigationActions {
        Button("Done") { console.userDismiss() }
          .accessibility(identifier: "wwn.guestConsole.done")
      } trailing: {
        EmptyView()
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
  }
}
#endif
