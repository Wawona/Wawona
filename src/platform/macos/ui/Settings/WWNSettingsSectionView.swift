#if os(macOS)
import AppKit
import SwiftUI
import WawonaModel

/// SwiftUI detail pane for one `WWNPreferencesSection`, replacing the AppKit
/// `WWNPreferencesContent` table. Rows mirror the AppKit controls 1:1 but with
/// native SwiftUI styling (System Settings look).
struct WWNSettingsSectionView: View {
    let section: WWNPreferencesSection
    @ObservedObject var model: WWNSettingsValueModel

    @State private var passwordItem: WWNSettingItem?
    @State private var passwordText = ""
    @State private var passwordRevealed = false

    var body: some View {
        if section.accessibilityIdentifier == "wwn.settings.environment" {
            // Env Vars (#157): embed the full SwiftUI inventory table instead
            // of the old "Open Environment Variables…" button row.
            EnvironmentVariablesView(preferences: WawonaPreferences.shared, perMachine: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        WWNSettingsRowView(
                            item: item,
                            model: model,
                            onPasswordEdit: { passwordItem = $0 }
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: Binding(
                get: { passwordItem != nil },
                set: { if !$0 { passwordItem = nil } }
            )) {
                if let item = passwordItem {
                    passwordSheet(for: item)
                }
            }
        }
    }

    private func passwordSheet(for item: WWNSettingItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.itemTitle(item))
                .font(.headline)
            if !model.itemDescription(item).isEmpty {
                Text(model.itemDescription(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if passwordRevealed {
                    TextField("Enter a Password...", text: $passwordText)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Enter a Password...", text: $passwordText)
                        .textFieldStyle(.roundedBorder)
                }
                Button {
                    passwordRevealed.toggle()
                } label: {
                    Image(systemName: passwordRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(passwordRevealed ? "Hide password" : "Show password")
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    passwordItem = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.setPassword(passwordText, for: item)
                    passwordItem = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// One settings row, rendered by `WWNSettingType` (same semantics as the
/// AppKit `WWNPreferencesContent` cell configuration).
private struct WWNSettingsRowView: View {
    let item: WWNSettingItem
    @ObservedObject var model: WWNSettingsValueModel
    var onPasswordEdit: (WWNSettingItem) -> Void = { _ in }

    private var title: String { model.itemTitle(item) }
    private var desc: String { model.itemDescription(item) }

    var body: some View {
        switch item.type {
        case .WSettingSwitch:
            switchRow
        case .WSettingText, .WSettingNumber:
            textRow
        case .WSettingPassword:
            passwordRow
        case .WSettingPopup:
            popupRow
        case .WSettingButton:
            buttonRow
        case .WSettingInfo:
            infoRow
        case .WSettingLink:
            linkRow
        case .WSettingHeader:
            headerRow
        default:
            EmptyView()
        }
    }

    // MARK: Row layouts

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var switchRow: some View {
        Toggle(isOn: model.boolBinding(for: item)) {
            titleStack
        }
        .disabled(!item.interactive)
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var textRow: some View {
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            TextField("", text: model.stringBinding(for: item))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
                .help(desc)
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var passwordRow: some View {
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Button(model.hasPassword(for: item) ? "Change…" : "Set…") {
                onPasswordEdit(item)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
    }

    private var popupRow: some View {
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Picker("", selection: model.popupBinding(for: item)) {
                ForEach(Array(model.popupOptions(for: item).enumerated()), id: \.offset) { index, option in
                    Text(option).tag(index)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 240)
            .disabled(!item.interactive)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var buttonRow: some View {
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Button(item.value(forKey: "key") as? String == "WaypipePreview" ? "Preview" : "Run") {
                item.actionBlock?()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Text(model.stringValue(for: item))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .lineLimit(nil)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            Button {
                model.copyValueToPasteboard(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var linkRow: some View {
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            if let urlString = item.urlString, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            }
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            WawonaAboutIconView()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }
}

/// Settings > About app icon. Same lookup chain as the AppKit header row
/// (dark asset first, then named asset, then bundled PNG).
private struct WawonaAboutIconView: View {
    private var image: NSImage? {
        if let img = NSImage(named: "Wawona-iOS-Dark-1024x1024@1x.png") { return img }
        if let path = Bundle.main.path(forResource: "Wawona-iOS-Dark-1024x1024@1x", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let img = NSImage(named: "Wawona") { return img }
        if let path = Bundle.main.path(forResource: "Wawona", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return nil
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: "display")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
