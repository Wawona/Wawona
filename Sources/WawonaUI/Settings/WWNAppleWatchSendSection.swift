#if os(iOS)
import SwiftUI
import WawonaUIContracts

/// Form list action (Settings.app style). Never `borderedProminent` inside
/// a `Form` Section: that paints a floating pill inside the list cell and
/// breaks row chrome / hit targets on iOS.
struct WWNAppleWatchSendSection: View {
    let canSend: Bool
    let sendFile: () -> Void
    @Environment(\.settingsSectionAccent) private var sectionAccent

    var body: some View {
        Section {
            Button(action: sendFile) {
                HStack(spacing: 12) {
                    Image(systemName: sendSymbolName)
                        .font(.body)
                        .foregroundColor(labelColor)
                        .frame(width: 22, alignment: .center)
                        .accessibility(hidden: true)
                    Text("Send File to Watch")
                        .foregroundColor(labelColor)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(!canSend)
            .accessibility(identifier: WWNA11y.settingsAppleWatchImport)
            .accessibility(label: Text("Send File to Watch"))
            .accessibility(hint: Text(
                canSend
                    ? "Opens the file picker and queues copies to the Watch inbox."
                    : "Pair an Apple Watch with Wawona installed to send files."
            ))
        } header: {
            Text("Send")
        } footer: {
            Text(footerText)
        }
    }

    private var labelColor: Color {
        canSend ? sectionAccent : Color.secondary
    }

    /// `applewatch.and.arrow.forward` is iOS 16+. Keep an iOS 13-safe glyph.
    private var sendSymbolName: String {
        if #available(iOS 16.0, *) {
            return "applewatch.and.arrow.forward"
        }
        return "square.and.arrow.up"
    }

    private var footerText: String {
        if canSend {
            return "Copies each file into Documents/Wawona/inbox on the Watch. A sleeping Watch receives the queue the next time it wakes."
        }
        return "Pair an Apple Watch and install Wawona on it before sending files."
    }
}
#endif
