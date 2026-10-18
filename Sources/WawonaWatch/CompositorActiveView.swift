#if os(watchOS)
import SwiftUI
import UIKit
import WawonaModel

struct CompositorActiveView: View {
    let profile: MachineProfile
    let session: MachineSession
    let sessions: SessionOrchestrator
    /// Leave this cover. Shell and compositor stay up for Tab Overview.
    var onPark: () -> Void = {}
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var preferences = WawonaPreferences.shared
    @StateObject private var startupLog = WatchStartupLogModel()
    @State private var showStopConfirmation = false
    @State private var draftText = ""
    @State private var consoleText = ""
    @State private var shell: WatchNativeShellSession?
    @State private var showTerminalActions = false
    /// Wayland client attached. Terminal parks; the client surface is the tab.
    @State private var clientSurfaceFront = false
    /// Edited text already typed on the shell prompt line (not yet run).
    @State private var lineHoldsDraft = false
    /// Bytes currently sitting on the prompt, so further edits send a diff.
    @State private var promptedLine = ""
    @State private var editingCommand = false
    @FocusState private var keyboardFocused: Bool

    private let commandDraftKey = "wwn.watch.terminal.draft"

    private var showsHostShellConsole: Bool {
        let session = NativeShellSession.from(profile: profile)
        return session.kind == .terminal && !session.useSSH
    }

    /// Shell or startup log covers the surface only until a Wayland client attaches.
    private var terminalInFront: Bool {
        showsHostShellConsole && !clientSurfaceFront
    }

    private func revealClientSurface() {
        clientSurfaceFront = true
        startupLog.dismiss()
    }

    private var requiresExitConfirmation: Bool {
        let resolved = preferences.resolvedSettings(for: profile)
        return resolved.shakeToCloseEnabled || resolved.swipeBackToCloseEnabled
    }

    private var startupClientLabel: String {
        let override = profile.runtimeOverrides.bundledAppID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty { return override }
        if let launcher = profile.launchers.first?.name, !launcher.isEmpty {
            return launcher
        }
        return profile.name
    }

    var body: some View {
        ZStack {
            WatchCompositorSurfaceView(onFirstFrame: {
                revealClientSurface()
            })
                .ignoresSafeArea()

            if showsHostShellConsole && !clientSurfaceFront {
                WatchGuestConsoleOverlay(text: consoleText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleTerminalActions() }
                    .modifier(WatchTerminalSafeArea(respect: preferences.respectSafeArea))
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if showTerminalActions {
                            WatchTerminalActions(
                                onSigterm: {
                                    promptedLine = ""
                                    lineHoldsDraft = false
                                    draftText = ""
                                    saveDraft()
                                    shell?.write("\u{03}")
                                    closeTerminalActions()
                                },
                                onEdit: { beginEditingCommand() },
                                onSend: {
                                    closeTerminalActions()
                                    sendDraft()
                                }
                            )
                        }
                    }
                    .zIndex(3)
            }

            if startupLog.isPresented && !showsHostShellConsole && !clientSurfaceFront {
                WatchStartupLogOverlay(
                    model: startupLog,
                    clientLabel: startupClientLabel,
                    onClose: parkSession
                )
                .modifier(WatchTerminalSafeArea(respect: preferences.respectSafeArea))
                .zIndex(2)
            }

            if !showsHostShellConsole {
                TextField("", text: $draftText)
                    .focused($keyboardFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.send)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
                    .onSubmit { commitDraft() }
            }
            Color.clear
                .frame(width: 0, height: 0)
                .onReceive(NotificationCenter.default.publisher(
                    for: Notification.Name("WWNGuestConsoleOutputNotification")
                )) { note in
                    if let chunk = note.userInfo?["text"] as? String {
                        consoleText += chunk
                        if consoleText.count > 16_384 {
                            consoleText = String(consoleText.suffix(16_384))
                        }
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: WWNWatchCompositorFrameReadyNotification
        )) { _ in
            WatchMachineThumbnailStore.captureIfEnabled(
                profile: profile,
                preferences: preferences,
                image: WWNWatchCompositorBridge.shared.latestFrame
            )
        }
        .onReceive(NotificationCenter.default.publisher(
            for: WWNWatchClientSurfaceNotification
        )) { note in
            let front = (note.userInfo?["front"] as? Bool) == true
            if front {
                revealClientSurface()
            } else {
                clientSurfaceFront = false
            }
        }
        .onAppear {
            if WWNWatchCompositorBridge.shared.clientSurfaceFront {
                revealClientSurface()
            }
            guard showsHostShellConsole else { return }
            draftText = UserDefaults.standard.string(forKey: commandDraftKey) ?? ""
            // Tab Overview Focus re-presents this view; reattach the live
            // shell instead of starting a second zsh.
            shell = WatchNativeShellRegistry.shared.attach(
                sessionId: session.id,
                onScreen: { consoleText = $0 },
                onFailure: { consoleText = $0 }
            )
        }
        .onDisappear {
            if showsHostShellConsole {
                WatchNativeShellRegistry.shared.detach(sessionId: session.id)
            }
        }
        .navigationTitle(terminalInFront ? "" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(terminalInFront ? .hidden : .automatic, for: .navigationBar)
        .toolbar(terminalInFront ? .hidden : .automatic, for: .bottomBar)
        .toolbar {
            if !terminalInFront {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        requestClose()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityIdentifier("wwn.watch.stop")
                    .accessibilityLabel("Stop")
                }
                if !startupLog.isPresented && !clientSurfaceFront {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Spacer(minLength: 0)
                            keyboardToolbarButton
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbarColorScheme(.dark, for: .bottomBar)
        .overlay(alignment: .leading) {
            WatchTerminalEdgeExit(onExit: parkSession)
                .ignoresSafeArea(edges: .leading)
        }
        .sheet(isPresented: $editingCommand) {
            NavigationStack {
                WatchTerminalEditor(draft: $draftText, onSync: syncDraftToPrompt)
            }
        }
        .confirmationDialog(
            "Stop Machine?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                disconnectActiveSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops \(profile.name) and returns to Machines.")
        }
        .onAppear {
            startupLog.attach()
        }
        .onDisappear {
            startupLog.dismiss()
        }
    }

    /// Bottom-trailing Liquid Glass keyboard control. Same toolbar slot as
    /// Whisperer's watch input strip; watchOS 26 uses native `.glass`.
    @ViewBuilder
    private var keyboardToolbarButton: some View {
        if #available(watchOS 26.0, *) {
            Button {
                draftText = ""
                keyboardFocused = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityIdentifier("wwn.watch.keyboard")
            .accessibilityLabel("Keyboard")
        } else {
            Button {
                draftText = ""
                keyboardFocused = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wwn.watch.keyboard")
            .accessibilityLabel("Keyboard")
        }
    }

    private func saveDraft() {
        UserDefaults.standard.set(draftText, forKey: commandDraftKey)
    }

    private func beginEditingCommand() {
        let onScreen = watchTerminalCommandLine(from: consoleText)
        if !onScreen.isEmpty {
            draftText = onScreen
            promptedLine = onScreen
            lineHoldsDraft = true
        } else if lineHoldsDraft {
            draftText = promptedLine
        }
        editingCommand = true
    }

    /// Keep the prompt line equal to the editor. A longer string appends.
    /// A shorter string sends backspaces. Anything else kills the line and
    /// retypes it, so the screen cannot drift from the field.
    private func syncDraftToPrompt(_ next: String) {
        guard next != promptedLine else { return }
        if next.hasPrefix(promptedLine) {
            shell?.write(String(next.dropFirst(promptedLine.count)))
        } else if promptedLine.hasPrefix(next) {
            let deleted = promptedLine.count - next.count
            shell?.write(String(repeating: "\u{7F}", count: deleted))
        } else {
            shell?.write("\u{15}" + next)
        }
        promptedLine = next
        lineHoldsDraft = !next.isEmpty
        saveDraft()
    }

    private func sendDraft() {
        if lineHoldsDraft {
            promptedLine = ""
            lineHoldsDraft = false
            shell?.write("\n")
            return
        }
        let text = draftText
        guard !text.isEmpty else { return }
        promptedLine = ""
        shell?.write(text.hasSuffix("\n") ? text : text + "\n")
    }

    private func toggleTerminalActions() {
        withAnimation(.smooth(duration: 0.2)) {
            showTerminalActions.toggle()
        }
    }

    private func closeTerminalActions() {
        withAnimation(.smooth(duration: 0.2)) {
            showTerminalActions = false
        }
    }

    /// Dismiss the terminal cover. The PTY and Wayland session keep running.
    private func parkSession() {
        keyboardFocused = false
        onPark()
    }

    private func requestClose() {
        if requiresExitConfirmation {
            showStopConfirmation = true
        } else {
            disconnectActiveSession()
        }
    }

    /// Native text-entry commit. The shell gets the text typed on its prompt
    /// line (Send runs it); Wayland clients get it as a soft keyboard commit.
    private func commitDraft() {
        if showsHostShellConsole {
            syncDraftToPrompt(draftText)
            return
        }
        let text = draftText
        guard !text.isEmpty else { return }
        draftText = ""
        // Append Return so shell commands execute (weston-terminal → zsh).
        WWNWatchCompositorBridge.shared.sendText(text.hasSuffix("\n") ? text : text + "\n")
    }

    private func disconnectActiveSession() {
        keyboardFocused = false
        if showsHostShellConsole {
            WatchNativeShellRegistry.shared.stop(sessionId: session.id)
            shell = nil
        }
        WatchMachineSessionBridge.disconnect(profile: profile)
        sessions.disconnect(sessionId: session.id)
        dismiss()
    }
}

/// Host shell text on watchOS. SpriteKit presents Wayland frames.
/// This view is the shell log. Metal is not linked.
private struct WatchTerminalSafeArea: ViewModifier {
    let respect: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if respect {
            content
        } else {
            content.ignoresSafeArea()
        }
    }
}

/// One row of terminal actions. Sits in the bottom safe area so the VT stays full width.
struct WatchTerminalActions: View {
    var onSigterm: () -> Void
    var onEdit: () -> Void
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            control("Sigterm", "exclamationmark.octagon", onSigterm)
            control("Edit", "pencil", onEdit)
            control("Send", "paperplane.fill", onSend)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wwn.terminal.actions")
    }

    private func control(
        _ title: String,
        _ symbol: String,
        _ run: @escaping () -> Void,
        tint: Color = .primary
    ) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .accessibilityLabel(title)
    }
}

/// Left-edge drag leaves the terminal. The session stays in Tab Overview.
struct WatchTerminalEdgeExit: View {
    var onExit: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 32)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 16, coordinateSpace: .local)
                    .onEnded { value in
                        let across = value.translation.width
                        let down = abs(value.translation.height)
                        guard across > 48, down < across else { return }
                        onExit()
                    }
            )
            .accessibilityAction(named: "Leave Terminal", onExit)
            .accessibilityIdentifier("wwn.terminal.done")
    }
}

struct WatchGuestConsoleOverlay: View {
    let text: String

    var body: some View {
        WatchTerminalScreen(text: text)
    }
}

/// Paints the mini compositor's latest SHM commit. Default present is SpriteKit
/// (`WatchSpritePresentView`). `WWN_WATCH_SK_PRESENT=0` keeps the CPU Image path
/// for A/B. Frames arrive on `WWNWatchCompositorFrameReadyNotification`.
struct WatchCompositorSurfaceView: View {
    var onFirstFrame: (() -> Void)? = nil
    @State private var frameID = 0
    @State private var didNotifyFirstFrame = false

    var body: some View {
        if PlatformCapabilities.watchPresentAcceleratorEnabled {
            WatchSpritePresentView(onFirstFrame: onFirstFrame)
        } else {
            cpuImagePresent
        }
    }

    private var cpuImagePresent: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image = WWNWatchCompositorBridge.shared.latestFrame {
                    let iw = CGFloat(image.width)
                    let ih = CGFloat(image.height)
                    let scale = min(
                        1,
                        min(geo.size.width / max(iw, 1), geo.size.height / max(ih, 1))
                    )
                    Image(uiImage: UIImage(cgImage: image))
                        .resizable()
                        .frame(width: iw * scale, height: ih * scale)
                        .id(frameID)
                } else if onFirstFrame == nil {
                    Text("Waiting for surface…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier("wwn.watch.compositorSurface")
        .accessibilityLabel("Wayland Surface")
        .onAppear {
            if WWNWatchCompositorBridge.shared.latestFrame != nil {
                notifyFirstFrameIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("WWNWatchCompositorFrameReadyNotification")
        )) { _ in
            frameID &+= 1
            notifyFirstFrameIfNeeded()
        }
    }

    private func notifyFirstFrameIfNeeded() {
        guard !didNotifyFirstFrame else { return }
        didNotifyFirstFrame = true
        onFirstFrame?()
    }
}
#endif
