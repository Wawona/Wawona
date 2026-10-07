#if WWN_PREFPANE && os(macOS)
import AppKit
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// System Settings owns the content-column width when
/// `NSPrefPaneSupportsAutoLayout` is set. Do not hard-cap the pane narrower
/// than the host (that is why Wawona looked unlike Network / Dock).
private enum PrefPaneMetrics {
    static let minWidth: CGFloat = 520
    static let minHeight: CGFloat = 480
}

private enum PrefPaneRoute: Hashable {
    case environment
    case picker(sectionID: String, itemKey: String)
}

/// System Settings → Wawona.
///
/// Layout matches **iOS Settings.app → Wawona** (`Settings.bundle` /
/// `WawonaSettings.plist`): one grouped Form, `PSGroupSpecifier`-style
/// sections, toggles and menus **inline**. Not a General-style hub of
/// section links that push empty shells.
///
/// Host chrome (General RE): toolbar back/forward is sidebar history only.
/// In-pane Back pops Env Vars / multi-value pages. Never remount with `.id`
/// on defaults write.
struct WawonaPrefPaneRootView: View {
    private let defaults: UserDefaults
    @State private var sections: [WWNPreferencesSection] = []
    @State private var path = NavigationPath()

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.aspauldingcode.Wawona")
        ?? .standard) {
        self.defaults = defaults
    }

    var body: some View {
        NavigationStack(path: $path) {
            PrefPaneFlatSettingsForm(
                sections: paneSections,
                defaults: defaults,
                path: $path,
                onCommit: reload
            )
            .navigationTitle("Wawona")
            .navigationDestination(for: PrefPaneRoute.self) { route in
                switch route {
                case .environment:
                    PrefPaneEnvironmentVariablesView()
                        .navigationTitle("Env Vars")
                case .picker(let sectionID, let itemKey):
                    if let section = paneSections.first(where: {
                        $0.accessibilityIdentifier == sectionID
                    }),
                        let item = section.items.first(where: { $0.key == itemKey }) {
                        PrefPanePickerPage(
                            item: item,
                            defaults: defaults,
                            onCommit: reload
                        )
                    } else {
                        Text("Setting unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if !path.isEmpty {
                    Button {
                        path.removeLast()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .help("Back to Wawona settings")
                }
            }
        }
        .frame(minWidth: PrefPaneMetrics.minWidth, minHeight: PrefPaneMetrics.minHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
    }

    private var paneSections: [WWNPreferencesSection] {
        let keep = Set(
            GlobalSettingsCatalog.systemSettingsPaneSections(for: .macOS)
                .map(\.objcAccessibilityIdentifier)
        )
        return sections.filter { keep.contains($0.accessibilityIdentifier) }
    }

    private func reload() {
        sections = WWNPreferencesSectionsBuilder.buildSections()
    }
}

// MARK: - Flat Form (iOS Settings.bundle shape)

/// One `Form` with a `Section` per catalog group. Rows are inline controls
/// (toggle / menu / text), matching `PreferenceSpecifiers` in
/// `WawonaSettings.plist`. Env Vars is the one child-pane push.
private struct PrefPaneFlatSettingsForm: View {
    let sections: [WWNPreferencesSection]
    let defaults: UserDefaults
    @Binding var path: NavigationPath
    var onCommit: () -> Void

    var body: some View {
        Form {
            ForEach(Array(sections.enumerated()), id: \.element.accessibilityIdentifier) { _, section in
                if section.accessibilityIdentifier == "wwn.settings.environment" {
                    Section {
                        NavigationLink(value: PrefPaneRoute.environment) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Environment Variables")
                                    Text(envStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                WawonaSettingsHubChrome.iconTile(
                                    systemName: section.icon.isEmpty ? "terminal" : section.icon,
                                    color: WawonaSettingsHubChrome.color(nsColor: section.iconColor)
                                )
                            }
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        Text("Edit overrides here. Same keys as the in-app Env Vars editor.")
                    }
                } else if section.items.isEmpty {
                    Section {
                        Text("No settings in this section.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(section.title)
                    }
                } else {
                    Section {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            PrefPaneInlineRow(
                                item: item,
                                defaults: defaults,
                                sectionID: section.accessibilityIdentifier,
                                path: $path,
                                onCommit: onCommit
                            )
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if let footer = sectionFooter(for: section) {
                            Text(footer)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var envStatus: String {
        let n = WawonaPreferences.shared.environmentOverrides.count
        return n == 0 ? "Catalog defaults" : "\(n) override\(n == 1 ? "" : "s")"
    }

    private func sectionFooter(for section: WWNPreferencesSection) -> String? {
        // Prefer a single shared footer when every row shares one desc, else omit
        // (iOS Settings.bundle uses per-group FooterText sparingly).
        let descs = section.items.compactMap { item -> String? in
            let d = item.desc.trimmingCharacters(in: .whitespacesAndNewlines)
            return d.isEmpty ? nil : d
        }
        guard let first = descs.first, descs.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }
}

/// Inline row: Settings.bundle PSToggle / PSMultiValue / PSTextField shape.
private struct PrefPaneInlineRow: View {
    let item: WWNSettingItem
    let defaults: UserDefaults
    let sectionID: String
    @Binding var path: NavigationPath
    var onCommit: () -> Void

    var body: some View {
        switch item.type {
        case .WSettingSwitch:
            Toggle(isOn: PrefPaneValue.boolBinding(item: item, defaults: defaults, onCommit: onCommit)) {
                Text(item.title)
                    .lineLimit(1)
            }
            .disabled(!item.interactive)

        case .WSettingPopup:
            // macOS System Settings: menu in the trailing column (not a forced
            // second page). Long option lists can still push a checkmark page.
            if item.options.count <= 8 {
                Picker(item.title, selection: PrefPaneValue.popupBinding(
                    item: item,
                    defaults: defaults,
                    onCommit: onCommit
                )) {
                    ForEach(Array(item.options.enumerated()), id: \.offset) { idx, label in
                        let value = item.optionValues.indices.contains(idx)
                            ? item.optionValues[idx]
                            : label
                        Text(label).tag(value)
                    }
                }
                .disabled(!item.interactive)
            } else {
                Button {
                    path.append(PrefPaneRoute.picker(sectionID: sectionID, itemKey: item.key))
                } label: {
                    HStack {
                        Text(item.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(PrefPaneValue.string(for: item, defaults: defaults))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!item.interactive)
            }

        case .WSettingText, .WSettingPassword, .WSettingNumber:
            LabeledContent(item.title) {
                Group {
                    if item.type == .WSettingPassword {
                        SecureField(
                            "",
                            text: PrefPaneValue.stringBinding(
                                item: item,
                                defaults: defaults,
                                onCommit: onCommit
                            )
                        )
                    } else {
                        TextField(
                            "",
                            text: PrefPaneValue.stringBinding(
                                item: item,
                                defaults: defaults,
                                onCommit: onCommit
                            )
                        )
                    }
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            }

        case .WSettingInfo:
            LabeledContent(item.title) {
                Text(PrefPaneValue.info(for: item, defaults: defaults))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

        case .WSettingLink:
            Button(item.buttonTitle.isEmpty ? item.title : item.buttonTitle) {
                if let url = URL(string: item.urlString) {
                    NSWorkspace.shared.open(url)
                }
            }

        case .WSettingButton:
            Button(item.buttonTitle.isEmpty ? item.title : item.buttonTitle) {
                // Stay inside System Settings when possible.
                if item.key.contains("DesktopReplacement") || item.key.contains("Sip") {
                    NotificationCenter.default.post(
                        name: Notification.Name(item.key),
                        object: nil
                    )
                }
                WawonaAppHandoff.openSettings(sectionTitle: nil)
            }

        default:
            EmptyView()
        }
    }
}

// MARK: - Multi-value checkmark page (iOS PSMultiValue when list is long)

private struct PrefPanePickerPage: View {
    let item: WWNSettingItem
    let defaults: UserDefaults
    var onCommit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(Array(item.options.enumerated()), id: \.offset) { idx, label in
                    let value = item.optionValues.indices.contains(idx)
                        ? item.optionValues[idx]
                        : label
                    Button {
                        PrefPaneValue.setString(value, item: item, defaults: defaults)
                        onCommit()
                        dismiss()
                    } label: {
                        HStack {
                            Text(label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if PrefPaneValue.rawString(for: item, defaults: defaults) == value {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                let d = item.desc.trimmingCharacters(in: .whitespacesAndNewlines)
                if !d.isEmpty {
                    Text(d)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(item.title)
    }
}

// MARK: - Shared UserDefaults helpers

private enum PrefPaneValue {
    static func info(for item: WWNSettingItem, defaults: UserDefaults) -> String {
        if let s = item.defaultValue as? String, !s.isEmpty { return s }
        return defaults.string(forKey: item.key) ?? ""
    }

    static func string(for item: WWNSettingItem, defaults: UserDefaults) -> String {
        let raw = rawString(for: item, defaults: defaults)
        if item.type == .WSettingPopup, !item.optionValues.isEmpty,
           let idx = item.optionValues.firstIndex(of: raw),
           item.options.indices.contains(idx) {
            return item.options[idx]
        }
        if item.type == .WSettingPopup, item.optionValues.isEmpty,
           let idx = Int(raw), item.options.indices.contains(idx) {
            return item.options[idx]
        }
        return raw
    }

    static func rawString(for item: WWNSettingItem, defaults: UserDefaults) -> String {
        if let s = defaults.string(forKey: item.key), !s.isEmpty { return s }
        if let n = defaults.object(forKey: item.key) as? NSNumber {
            return n.stringValue
        }
        if let s = item.defaultValue as? String { return s }
        if let n = item.defaultValue as? Int { return String(n) }
        if let n = item.defaultValue as? NSNumber { return n.stringValue }
        return ""
    }

    static func setString(_ newValue: String, item: WWNSettingItem, defaults: UserDefaults) {
        if item.type == .WSettingNumber, let n = Int(newValue) {
            defaults.set(n, forKey: item.key)
        } else if item.type == .WSettingPopup {
            if !item.optionValues.isEmpty {
                defaults.set(newValue, forKey: item.key)
            } else if let idx = item.options.firstIndex(of: newValue) {
                defaults.set(idx, forKey: item.key)
            } else {
                defaults.set(newValue, forKey: item.key)
            }
        } else {
            defaults.set(newValue, forKey: item.key)
        }
        defaults.synchronize()
    }

    static func boolBinding(
        item: WWNSettingItem,
        defaults: UserDefaults,
        onCommit: @escaping () -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                if defaults.object(forKey: item.key) == nil {
                    return item.defaultValue as? Bool ?? false
                }
                return defaults.bool(forKey: item.key)
            },
            set: { newValue in
                defaults.set(newValue, forKey: item.key)
                defaults.synchronize()
                onCommit()
            }
        )
    }

    static func stringBinding(
        item: WWNSettingItem,
        defaults: UserDefaults,
        onCommit: @escaping () -> Void
    ) -> Binding<String> {
        Binding(
            get: { rawString(for: item, defaults: defaults) },
            set: { newValue in
                setString(newValue, item: item, defaults: defaults)
                onCommit()
            }
        )
    }

    static func popupBinding(
        item: WWNSettingItem,
        defaults: UserDefaults,
        onCommit: @escaping () -> Void
    ) -> Binding<String> {
        Binding(
            get: { rawString(for: item, defaults: defaults) },
            set: { newValue in
                setString(newValue, item: item, defaults: defaults)
                onCommit()
            }
        )
    }
}

/// Hosting view fills the System Settings content column (Auto Layout).
final class WawonaPrefPaneHostingView: NSView {
    private var hosting: NSHostingView<AnyView>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = AnyView(
            WawonaPrefPaneRootView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 13.0, *) {
            host.sizingOptions = [.minSize]
        }
        addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: PrefPaneMetrics.minWidth),
            heightAnchor.constraint(greaterThanOrEqualToConstant: PrefPaneMetrics.minHeight),
        ])
        hosting = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: PrefPaneMetrics.minWidth, height: PrefPaneMetrics.minHeight)
    }
}
#endif
