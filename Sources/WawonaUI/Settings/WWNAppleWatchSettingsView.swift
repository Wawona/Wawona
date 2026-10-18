#if os(iOS)
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// iPhone and iPad Apple Watch settings. Sends files with WatchConnectivity.
/// Watch Global Settings stay on the wrist. This screen is send-side only.
struct WWNAppleWatchSettingsView: View {
    @State private var status = WatchCompanionController.shared.status()
    @State private var outstanding: [WatchOutstandingTransfer] = []
    @State private var showingImporter = false
    @State private var notice = ""
    @State private var showNotice = false

    private var canSend: Bool {
        status.paired && status.watchAppInstalled
    }

    var body: some View {
        Form {
            WWNAppleWatchStatusSection(status: status)
            WWNAppleWatchSendSection(canSend: canSend, sendFile: presentImporter)
            WWNAppleWatchTransfersSection(
                summary: status.lastTransferSummary,
                outstanding: outstanding
            )
        }
        .backport.dismissKeyboardOnScroll()
        .backport.fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: sendPickedFiles
        )
        .alert(isPresented: $showNotice) {
            Alert(
                title: Text("Could Not Send"),
                message: Text(notice),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear(perform: activateAndRefresh)
        .onReceive(
            NotificationCenter.default.publisher(for: WWNWatchCompanionTransferDidChange)
        ) { _ in
            refresh()
        }
        .accessibilityElement(children: .contain)
        .accessibility(identifier: WWNA11y.settingsAppleWatch)
    }

    private func presentImporter() {
        showingImporter = true
    }

    private func activateAndRefresh() {
        WatchCompanionController.shared.activate()
        refresh()
    }

    private func refresh() {
        status = WatchCompanionController.shared.status()
        outstanding = WatchCompanionController.shared.outstandingTransfers()
    }

    private func sendPickedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            if isCancellation(error) {
                return
            }
            notice = error.localizedDescription
            showNotice = true
        case .success(let urls):
            var firstFailure: String?
            for url in urls {
                let sent = WatchCompanionController.shared.stageAndSend(securityScopedSource: url)
                if case .failed(let message) = sent, firstFailure == nil {
                    firstFailure = message
                }
            }
            if let firstFailure {
                notice = firstFailure
                showNotice = true
            }
            refresh()
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError
    }
}
#endif
