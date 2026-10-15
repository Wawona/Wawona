#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// SwiftUI detail pane for one `WWNPreferencesSection`, replacing the AppKit
/// `WWNPreferencesContent` table. Rows mirror the AppKit controls 1:1 but with
/// native SwiftUI styling (System Settings look).
struct WWNSettingsSectionView: View {
    let section: WWNPreferencesSection
    @ObservedObject var model: WWNSettingsValueModel

    private var sectionAccent: Color { section.swiftUIIconColor }

    var body: some View {
        Group {
            if section.accessibilityIdentifier == "wwn.settings.environment" {
                EnvironmentVariablesView(preferences: WawonaPreferences.shared, perMachine: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    if section.accessibilityIdentifier == "wwn.settings.desktop" {
                        desktopFormSections
                    } else {
                        Section {
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                WWNSettingsRowView(item: item, model: model)
                                    .backport.visibleRowSeparator()
                            }
                        }
                    }
                }
                #if os(macOS)
                .backport.groupedForm()
                #endif
                #if os(iOS)
                .backport.dismissKeyboardOnScroll()
                #endif
                #if os(iOS) || os(visionOS)
                .onDisappear { WWNHostKeyboard.dismiss() }
                #endif
            }
        }
        // Section accent tints detail controls (Toggle / Picker / Button /
        // Link), matching Android section accents. Not sidebar icon tiles.
        .settingsSectionAccent(sectionAccent)
        .backport.tint(sectionAccent)
    }

    /// Desktop Replacement detail: labelled Desktop vs Lock Screen groups.
    @ViewBuilder
    private var desktopFormSections: some View {
        let desktopItems = section.items.filter { !Self.isLockScreenItem($0) }
        let lockItems = section.items.filter { Self.isLockScreenItem($0) }
        if !desktopItems.isEmpty {
            Section {
                ForEach(Array(desktopItems.enumerated()), id: \.offset) { _, item in
                    WWNSettingsRowView(item: item, model: model)
                        .backport.visibleRowSeparator()
                }
            } header: {
                Text("Desktop")
                    .foregroundColor(sectionAccent)
            }
        }
        if !lockItems.isEmpty {
            Section {
                ForEach(Array(lockItems.enumerated()), id: \.offset) { _, item in
                    WWNSettingsRowView(item: item, model: model)
                        .backport.visibleRowSeparator()
                }
            } header: {
                Text("Lock Screen")
                    .foregroundColor(sectionAccent)
            }
        }
    }

    private static func isLockScreenItem(_ item: WWNSettingItem) -> Bool {
        let key = item.key.lowercased()
        let title = item.title.lowercased()
        return key.contains("lockscreen") || title.contains("lock screen")
    }
}

/// One settings row, rendered by `WWNSettingType` (same semantics as the
/// AppKit `WWNPreferencesContent` cell configuration).
private struct WWNSettingsRowView: View {
    let item: WWNSettingItem
    @ObservedObject var model: WWNSettingsValueModel
    @Environment(\.settingsSectionAccent) private var sectionAccent
    @State private var showingHelp = false
    @State private var numberText = ""

    /// iOS / tvOS / visionOS: text and password open a push editor (Settings.app).
    /// macOS keeps inline fields (and a push password editor).
    private var usesPushTextEditor: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    private var usesPushPasswordEditor: Bool { true }

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
    /// One-line subtitle: first non-empty desc line, capped.
    private var compactDescription: String {
        let first = desc
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
        guard !first.isEmpty, first.count <= 88 else { return "" }
        return first
    }
    private var hasDetailedHelp: Bool {
        if item.type == .WSettingInfo {
            // Info circle when there is more than the one-line role preview.
            let lines = desc.split(separator: "\n", omittingEmptySubsequences: true)
            return lines.count > 1 || (!desc.isEmpty && compactDescription.isEmpty)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !compactDescription.isEmpty {
                Text(compactDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var helpButton: some View {
        WawonaButton {
            showingHelp = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibility(label: Text("Help for \(title)"))
        #if os(macOS)
        .help("More information")
        #endif
    }

    private var switchRow: some View {
        rowLayout {
            Toggle("", isOn: model.boolBinding(for: item))
                .labelsHidden()
                .toggleStyle(.switch)
                .backport.controlSize(.regular)
                .backport.tint(sectionAccent)
                .accessibility(label: Text(title))
        }
        .disabled(!item.interactive)
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
    }

    @ViewBuilder
    private var textRow: some View {
        if usesPushTextEditor {
            pushValueRow(
                preview: model.stringValue(for: item),
                emptyPreview: "Not Set",
                kind: .text,
                initial: model.stringValue(for: item)
            ) { model.setString($0, for: item) }
        } else {
            let prompt = model.textPrompt(for: item)
            rowLayout {
                WawonaTextField(
                    "",
                    text: model.stringBinding(for: item),
                    prompt: prompt.isEmpty ? nil : Text(prompt)
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .backport.doneSubmitLabel()
                .accessibility(label: Text(title))
                .accessibility(identifier: item.accessibilityIdentifier ?? "")
                #if os(macOS)
                .help(desc)
                #endif
            }
            .accessibility(identifier: item.accessibilityIdentifier ?? "")
        }
    }

    private var numberRow: some View {
        let spec = model.numberSpec(for: item)
        return rowLayout {
            HStack(spacing: 6) {
                WawonaTextField(
                    "",
                    text: $numberText,
                    prompt: Text(spec.promptText)
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .backport.doneSubmitLabel()
                .accessibility(label: Text(title))

                #if !os(tvOS)
                Stepper(
                    "",
                    value: Binding(
                        get: {
                            let val = model.integerValue(for: item)
                            return min(max(val, spec.range.lowerBound), spec.range.upperBound)
                        },
                        set: {
                            let clamped = min(max($0, spec.range.lowerBound), spec.range.upperBound)
                            numberText = String(clamped)
                            DispatchQueue.main.async { model.setNumberText(String(clamped), for: item) }
                        }
                    ),
                    in: spec.range,
                    step: spec.step
                )
                .labelsHidden()
                .accessibility(label: Text("\(title) stepper"))
                #endif
            }
            .onAppear {
                let stored = model.stringValue(for: item)
                numberText = spec.allowsEmpty && stored.isEmpty
                    ? ""
                    : String(model.integerValue(for: item))
            }
            .backport.onChange(of: numberText) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                guard let parsed = Int(digits) else {
                    if numberText != digits { numberText = digits }
                    if spec.allowsEmpty && model.stringValue(for: item) != "" {
                        DispatchQueue.main.async { model.setNumberText("", for: item) }
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
            .backport.onSubmit {
                commitNumberIfChanged(spec)
                numberText = spec.allowsEmpty && numberText.isEmpty
                    ? ""
                    : String(model.integerValue(for: item))
            }
        }
        .disabled(!item.interactive)
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
        .onDisappear {
            DispatchQueue.main.async { commitNumberIfChanged(spec) }
        }
    }

    private func commitNumberIfChanged(_ spec: WWNSettingsValueModel.NumberSpec) {
        let stored = model.stringValue(for: item)
        let displayedStored = spec.allowsEmpty && stored.isEmpty
            ? ""
            : String(model.integerValue(for: item))
        guard numberText != displayedStored else { return }
        DispatchQueue.main.async { model.setNumberText(numberText, for: item) }
    }

    @ViewBuilder
    private var passwordRow: some View {
        if usesPushPasswordEditor {
            pushValueRow(
                preview: model.hasPassword(for: item) ? "••••••••" : "",
                emptyPreview: "Not Set",
                kind: .password,
                initial: model.passwordValue(for: item)
            ) { model.setPassword($0, for: item) }
        } else {
            EmptyView()
        }
    }

    private func pushValueRow(
        preview: String,
        emptyPreview: String,
        kind: WWNSettingsTextEditorView.Kind,
        initial: String,
        onSave: @escaping (String) -> Void
    ) -> some View {
        let shown = preview.isEmpty ? emptyPreview : preview
        return NavigationLink(destination: WWNSettingsTextEditorView(
            title: title,
            helpText: desc,
            prompt: model.textPrompt(for: item),
            kind: kind,
            initialValue: initial,
            onSave: onSave
        )) {
            HStack(spacing: 12) {
                titleStack
                Spacer(minLength: 12)
                Text(shown)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if hasDetailedHelp {
                    helpButton
                }
            }
        }
        .modifier(WWNSettingsHelpPresentationModifier(
            title: title,
            bodyText: detailedHelp,
            isPresented: $showingHelp
        ))
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
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
            .backport.menuPicker()
            #endif
            .backport.tint(sectionAccent)
            .disabled(!item.interactive)
            .accessibility(label: Text(title))
            .accessibility(identifier: item.accessibilityIdentifier ?? "")
        }
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
    }

    private var buttonRow: some View {
        let presentation = model.actionPresentation(for: item)
        return rowLayout {
            WawonaButton(presentation.title, systemImage: presentation.systemImage) {
                DispatchQueue.main.async {
                    model.performButtonAction(for: item)
                }
            }
            .backport.borderedButton()
            .backport.tint(sectionAccent)
            .accessibility(identifier: item.accessibilityIdentifier ?? "")
        }
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
    }

    private var infoRow: some View {
        HStack(spacing: 12) {
            if !item.iconURL.isEmpty, let url = URL(string: item.iconURL) {
                WWNSettingsLinkIcon(url: url)
            }
            titleStack
            Spacer(minLength: 12)
            HStack(alignment: .center, spacing: 10) {
                Text(model.stringValue(for: item))
                    #if !os(tvOS)
                    .backport.selectableText()
                    #endif
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .accessibility(identifier: item.accessibilityIdentifier ?? "")
                #if !os(tvOS)
                WawonaButton {
                    model.copyValueToPasteboard(item)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                #if os(macOS)
                .help("Copy to clipboard")
                #endif
                #endif
                if hasDetailedHelp {
                    helpButton
                }
            }
        }
        .modifier(WWNSettingsHelpPresentationModifier(
            title: title,
            bodyText: detailedHelp,
            isPresented: $showingHelp
        ))
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
    }

    private var linkRow: some View {
        let presentation = model.linkPresentation(for: item)
        return HStack(spacing: 12) {
            if !item.iconURL.isEmpty, let url = URL(string: item.iconURL) {
                WWNSettingsLinkIcon(url: url)
            }
            titleStack
            Spacer(minLength: 12)
            if !item.urlString.isEmpty, let url = URL(string: item.urlString) {
                WawonaLink(destination: url) {
                    // Tight label: avoid Label's default icon/title gap.
                    HStack(spacing: 4) {
                        Text(presentation.title)
                        Image(systemName: presentation.systemImage)
                    }
                }
                .backport.tint(sectionAccent)
                .accessibility(identifier: item.accessibilityIdentifier ?? "")
            }
        }
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            WawonaAboutIconView()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20).weight(.semibold))
                if !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !item.urlString.isEmpty, let url = URL(string: item.urlString) {
                    let visit = item.buttonTitle.isEmpty ? "Visit" : item.buttonTitle
                    WawonaLink(destination: url) {
                        HStack(spacing: 4) {
                            Text(visit)
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .accessibility(label: Text("\(visit) wawona.io"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibility(identifier: item.accessibilityIdentifier ?? "")
    }

    @ViewBuilder
    private func rowLayout<Control: View>(
        @ViewBuilder control: () -> Control
    ) -> some View {
        WawonaFittingRow {
            HStack(spacing: 12) {
                titleStack
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    control()
                        .frame(width: controlWidth, alignment: .trailing)
                    if hasDetailedHelp {
                        helpButton
                    }
                }
            }
        } vertical: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    titleStack
                    Spacer(minLength: 0)
                    if hasDetailedHelp {
                        helpButton
                    }
                }
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .modifier(WWNSettingsHelpPresentationModifier(
            title: title,
            bodyText: detailedHelp,
            isPresented: $showingHelp
        ))
    }
}

/// Attach sheet / popover / alert for the info button.
private struct WWNSettingsHelpPresentationModifier: ViewModifier {
    let title: String
    let bodyText: String
    @Binding var isPresented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content.alert(title, isPresented: $isPresented) {
            WawonaButton("OK", role: .cancel) {}
        } message: {
            Text(bodyText)
        }
        #elseif os(macOS)
        content.popover(isPresented: $isPresented) {
            WWNSettingsHelpSheet(title: title, bodyText: bodyText)
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 420)
                .frame(maxHeight: 360)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            WWNSettingsHelpSheet(title: title, bodyText: bodyText)
                .modifier(WWNSettingsHelpSheetChrome())
        }
        #endif
    }
}

/// Compact About / Dependencies help: bottom sheet (iOS) or popover (macOS).
private struct WWNSettingsHelpSheet: View {
    let title: String
    let bodyText: String
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS) || os(visionOS)
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                WawonaButton("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            #else
            Text(title)
                .font(.headline)
            #endif
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        if let url = URL(string: paragraph),
                           let scheme = url.scheme?.lowercased(),
                           scheme == "http" || scheme == "https" {
                            WawonaLink(destination: url) {
                                Text(paragraph)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)
                            }
                        } else {
                            Text(paragraph)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                #if !os(tvOS) && !os(watchOS)
                                .backport.selectableText()
                                #endif
                        }
                    }
                    ForEach(embeddedLinks, id: \.absoluteString) { url in
                        WawonaLink(destination: url) {
                            HStack(spacing: 4) {
                                Text(url.absoluteString)
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.footnote)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paragraphs: [String] {
        bodyText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// URLs mentioned inside prose lines (not already a whole-line link).
    private var embeddedLinks: [URL] {
        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        )
        let ns = bodyText as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = detector?.matches(in: bodyText, options: [], range: range) ?? []
        var urls: [URL] = []
        for match in matches {
            guard let url = match.url else { continue }
            let whole = paragraphs.contains(where: { $0 == url.absoluteString })
            if !whole { urls.append(url) }
        }
        return urls
    }
}

#if os(iOS) || os(visionOS)
/// Fit-to-content bottom sheet when the OS allows custom detents.
private struct WWNSettingsHelpSheetChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, visionOS 1.0, *) {
            content
                .presentationDetents([.height(220), .medium])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
#endif


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
                    .foregroundColor(.secondary)
                    .padding(2)
            }
        }
        .frame(width: 28, height: 28)
        .backport.background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibility(hidden: true)
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
                .foregroundColor(.secondary)
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

