import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Prompt / New Tab / New Window when Default Start Type is Prompt and the
/// host can open another window. macOS uses `NSAlert`; iPad / iPhone 15+ /
/// visionOS use `confirmationDialog` (legacy `actionSheet` is invisible on
/// visionOS spatial UI, so Start looked like a no-op). tvOS never prompts
/// (tab only).
struct WWNMachineStartPlacementPrompt: ViewModifier {
    @ObservedObject var model: WWNMachinesViewModel

    func body(content: Content) -> some View {
        #if os(macOS)
        content.backport.onChange(of: model.pendingStartProfile?.machineId) { _, _ in
            presentMacAlertIfNeeded()
        }
        #elseif os(visionOS)
        content.confirmationDialog(
            "Start",
            isPresented: pendingBinding,
            titleVisibility: .visible
        ) {
            Button("New Tab") { model.confirmStartInNewTab() }
            Button("New Window") { model.confirmStartInNewWindow() }
            Button("Cancel", role: .cancel) { model.cancelPendingStart() }
        } message: {
            Text("Open this machine in a tab or in a new window?")
        }
        #elseif os(iOS)
        // confirmationDialog is iOS 15+. Floor is 13.0: keep actionSheet there.
        if #available(iOS 15.0, *) {
            content.confirmationDialog(
                "Start",
                isPresented: pendingBinding,
                titleVisibility: .visible
            ) {
                Button("New Tab") { model.confirmStartInNewTab() }
                Button("New Window") { model.confirmStartInNewWindow() }
                Button("Cancel", role: .cancel) { model.cancelPendingStart() }
            } message: {
                Text("Open this machine in a tab or in a new window?")
            }
        } else {
            content.actionSheet(isPresented: pendingBinding) {
                ActionSheet(
                    title: Text("Start"),
                    message: Text("Open this machine in a tab or in a new window?"),
                    buttons: [
                        .default(Text("New Tab")) { model.confirmStartInNewTab() },
                        .default(Text("New Window")) { model.confirmStartInNewWindow() },
                        .cancel { model.cancelPendingStart() },
                    ]
                )
            }
        }
        #else
        content
        #endif
    }

    #if os(iOS) || os(visionOS)
    private var pendingBinding: Binding<Bool> {
        Binding(
            get: { model.pendingStartProfile != nil },
            set: { presented in
                if !presented, model.pendingStartProfile != nil {
                    model.cancelPendingStart()
                }
            }
        )
    }
    #endif

    #if os(macOS)
    private func presentMacAlertIfNeeded() {
        guard model.pendingStartProfile != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Start"
        alert.informativeText = "Open this machine in a tab or in a new window?"
        alert.addButton(withTitle: "New Tab")
        alert.addButton(withTitle: "New Window")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.confirmStartInNewTab()
        case .alertSecondButtonReturn:
            model.confirmStartInNewWindow()
        default:
            model.cancelPendingStart()
        }
    }
    #endif
}
