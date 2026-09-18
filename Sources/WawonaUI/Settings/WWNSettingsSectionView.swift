#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            #if os(iOS)
            .scrollDismissesKeyboard(.immediately)
            #endif
            #if os(iOS) || os(visionOS)
            .onDisappear { WWNHostKeyboard.dismiss() }
            #endif
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
                #if os(macOS)
                .help(passwordRevealed ? "Hide password" : "Show password")
                #endif
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    passwordItem = nil
                }
                #if !os(tvOS)
                .keyboardShortcut(.cancelAction)
                #endif
                Button("Save") {
                    model.setPassword(passwordText, for: item)
                    passwordItem = nil
                }
                #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
                #endif
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 420)
        #endif
    }
}

/// One settings row, rendered by `WWNSettingType` (same semantics as the
/// AppKit `WWNPreferencesContent` cell configuration).
private struct WWNSettingsRowView: View {
    let item: WWNSettingItem
    @ObservedObject var model: WWNSettingsValueModel
    var onPasswordEdit: (WWNSettingItem) -> Void = { _ in }
    @State private var showingHelp = false

    private var title: String { model.itemTitle(item) }
    private var desc: String { model.itemDescription(item) }
    private var compactDescription: String {
        let normalized = desc.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard normalized.count <= 88 else { return "" }
        return normalized
    }
    private var hasDetailedHelp: Bool {
        !desc.isEmpty && compactDescription != desc.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private var controlWidth: CGFloat {
        #if os(macOS)
        240
        #elseif os(tvOS)
        300
        #else
        180
        #endif
    }

    var body: some View {
        switch item.type {
        case .WSettingSwitch:
            switchRow
        case .WSettingText:
            textRow
        case .WSettingNumber:
            numberRow
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
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !compactDescription.isEmpty {
                    Text(compactDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if hasDetailedHelp {
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Help for \(title)")
                #if os(macOS)
                .help("More information")
                #endif
                .popover(isPresented: $showingHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline)
                        Text(desc)
                    }
                    .padding()
                    .frame(idealWidth: 320)
                }
            }
        }
    }

    private var switchRow: some View {
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Toggle("", isOn: model.boolBinding(for: item))
                .labelsHidden()
                .frame(width: controlWidth, alignment: .trailing)
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
                .frame(width: controlWidth)
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
                #if os(macOS)
                .help(desc)
                #endif
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var numberRow: some View {
        let spec = model.numberSpec(for: item)
        return HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Stepper(
                value: model.integerBinding(for: item),
                in: spec.range,
                step: spec.step
            ) {
                Text(model.integerValue(for: item), format: .number)
                    .monospacedDigit()
            }
            .frame(width: controlWidth, alignment: .trailing)
            .accessibilityLabel(title)
            .accessibilityValue(Text(model.integerValue(for: item), format: .number))
        }
        .disabled(!item.interactive)
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
            .frame(width: controlWidth, alignment: .trailing)
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
            #if os(tvOS)
            .pickerStyle(.navigationLink)
            #else
            .pickerStyle(.menu)
            #endif
            .frame(width: controlWidth)
            .disabled(!item.interactive)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var buttonRow: some View {
        let presentation = model.actionPresentation(for: item)
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Button(presentation.title, systemImage: presentation.systemImage) {
                item.actionBlock?()
            }
            .buttonStyle(.bordered)
            .frame(width: controlWidth, alignment: .trailing)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            Text(model.stringValue(for: item))
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
                .foregroundStyle(.secondary)
                .frame(width: controlWidth - 34, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            Button {
                model.copyValueToPasteboard(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            #if os(macOS)
            .help("Copy to clipboard")
            #endif
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var linkRow: some View {
        let presentation = model.linkPresentation(for: item)
        HStack(spacing: 12) {
            titleStack
            Spacer(minLength: 12)
            if let urlString = item.urlString, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(presentation.title, systemImage: presentation.systemImage)
                }
                .frame(width: controlWidth, alignment: .trailing)
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
    var body: some View {
        if let image = aboutImage() {
            image
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: "display")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }

    private func aboutImage() -> Image? {
        let names = ["Wawona-iOS-Dark-1024x1024@1x", "Wawona"]
        #if os(macOS)
        for name in names {
            if let img = NSImage(named: name) { return Image(nsImage: img) }
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let img = NSImage(contentsOfFile: path) {
                return Image(nsImage: img)
            }
        }
        #else
        for name in names {
            if let img = UIImage(named: name) { return Image(uiImage: img) }
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let img = UIImage(contentsOfFile: path) {
                return Image(uiImage: img)
            }
        }
        #endif
        return nil
    }
}
#endif
