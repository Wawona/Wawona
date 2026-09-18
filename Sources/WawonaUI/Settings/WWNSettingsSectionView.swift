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
                        // Keep a separator after every row, including after
                        // an iOS split-detail restoration.
                        .backport.visibleRowSeparator()
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
    @State private var numberText = ""

    private var title: String { model.itemTitle(item) }
    private var desc: String { model.itemDescription(item) }
    private var detailedHelp: String {
        if item.type == .WSettingInfo {
            return [model.stringValue(for: item), desc]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
        return desc
    }
    private var compactDescription: String {
        let normalized = desc.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard normalized.count <= 88 else { return "" }
        return normalized
    }
    private var hasDetailedHelp: Bool {
        if item.type == .WSettingInfo {
            return !detailedHelp.isEmpty
        }
        let normalized = desc.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return !desc.isEmpty && compactDescription != normalized
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
                helpButton
            }
        }
    }

    @ViewBuilder
    private var helpButton: some View {
        let button = Button {
            showingHelp = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Help for \(title)")

        #if os(tvOS)
        button.alert(title, isPresented: $showingHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(detailedHelp)
        }
        #else
        button
            #if os(macOS)
            .help("More information")
            #endif
            .popover(isPresented: $showingHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(detailedHelp)
                }
                .padding()
                .frame(idealWidth: 320)
            }
        #endif
    }

    private var switchRow: some View {
        rowLayout {
            Toggle("", isOn: model.boolBinding(for: item))
                .labelsHidden()
                .accessibilityLabel(title)
        }
        .disabled(!item.interactive)
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var textRow: some View {
        rowLayout {
            TextField("", text: model.stringBinding(for: item))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
                .accessibilityLabel(title)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
                #if os(macOS)
                .help(desc)
                #endif
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var numberRow: some View {
        let spec = model.numberSpec(for: item)
        return rowLayout {
            TextField(
                "",
                text: $numberText,
                prompt: Text(spec.allowsEmpty ? "Auto" : "\(spec.defaultValue)")
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .submitLabel(.done)
            .accessibilityLabel(title)
            .onAppear {
                let stored = model.stringValue(for: item)
                numberText = spec.allowsEmpty && stored.isEmpty
                    ? ""
                    : String(model.integerValue(for: item))
            }
            .onChange(of: numberText) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                guard let parsed = Int(digits) else {
                    if numberText != digits { numberText = digits }
                    if spec.allowsEmpty && model.stringValue(for: item) != "" {
                        model.setNumberText("", for: item)
                    }
                    return
                }
                let clamped = min(parsed, spec.range.upperBound)
                let normalized = String(clamped)
                if numberText != normalized {
                    numberText = normalized
                }
                if clamped >= spec.range.lowerBound {
                    commitNumberIfChanged(spec)
                }
            }
            .onSubmit {
                commitNumberIfChanged(spec)
                numberText = spec.allowsEmpty && numberText.isEmpty
                    ? ""
                    : String(model.integerValue(for: item))
            }
        }
        .disabled(!item.interactive)
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        .onDisappear {
            commitNumberIfChanged(spec)
        }
    }

    private func commitNumberIfChanged(_ spec: WWNSettingsValueModel.NumberSpec) {
        let stored = model.stringValue(for: item)
        let displayedStored = spec.allowsEmpty && stored.isEmpty
            ? ""
            : String(model.integerValue(for: item))
        guard numberText != displayedStored else { return }
        model.setNumberText(numberText, for: item)
    }

    private var passwordRow: some View {
        rowLayout {
            Button(model.hasPassword(for: item) ? "Change…" : "Set…") {
                onPasswordEdit(item)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
    }

    private var popupRow: some View {
        rowLayout {
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
            .disabled(!item.interactive)
            .accessibilityLabel(title)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var buttonRow: some View {
        let presentation = model.actionPresentation(for: item)
        return rowLayout {
            Button(presentation.title, systemImage: presentation.systemImage) {
                item.actionBlock?()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var infoRow: some View {
        rowLayout {
            HStack(alignment: .top, spacing: 8) {
                Text(model.stringValue(for: item))
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
                #if !os(tvOS)
            Button {
                model.copyValueToPasteboard(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            #if os(macOS)
            .help("Copy to clipboard")
            #endif
                #endif
            }
        }
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
    }

    private var linkRow: some View {
        let presentation = model.linkPresentation(for: item)
        return HStack(spacing: 12) {
            if let iconURL = item.iconURL, let url = URL(string: iconURL) {
                WWNSettingsLinkIcon(url: url)
            }
            titleStack
            Spacer(minLength: 12)
            if let urlString = item.urlString, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(presentation.title, systemImage: presentation.systemImage)
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

    @ViewBuilder
    private func rowLayout<Control: View>(
        @ViewBuilder control: () -> Control
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                titleStack
                Spacer(minLength: 12)
                control()
                    .frame(width: controlWidth, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                titleStack
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// The iOS settings table retains the same leading identity icons as its
/// UIKit counterpart.  A symbol placeholder reserves the row geometry while
/// a remote avatar or service mark is loading (or unavailable).
private struct WWNSettingsLinkIcon: View {
    let url: URL
    // `StateObject` starts at iOS 14; this view must also compile for iOS 13.
    @ObservedObject private var loader: WWNSettingsRemoteImageLoader

    init(url: URL) {
        self.url = url
        loader = WWNSettingsRemoteImageLoader(url: url)
    }

    var body: some View {
        Group {
            if let image = loader.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .frame(width: 28, height: 28)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// `AsyncImage` is unavailable on iOS 13–14.  This native UI adapter keeps
/// the About links visually equivalent without raising Wawona's SwiftUI floor.
private final class WWNSettingsRemoteImageLoader: ObservableObject {
    @Published private(set) var image: Image?

    init(url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { return }
            #if os(macOS)
            guard let platformImage = NSImage(data: data) else { return }
            let image = Image(nsImage: platformImage)
            #else
            guard let platformImage = UIImage(data: data) else { return }
            let image = Image(uiImage: platformImage)
            #endif
            DispatchQueue.main.async {
                self?.image = image
            }
        }.resume()
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
