import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension WawonaBackport where Content: View {
    @ViewBuilder func selectableText() -> some View {
        #if os(tvOS)
        content
        #else
        if #available(iOS 15.0, watchOS 8.0, macOS 12.0, *) {
            content.textSelection(.enabled)
        } else { content }
        #endif
    }

    @ViewBuilder func groupedForm() -> some View {
        if #available(iOS 16.0, tvOS 16.0, watchOS 9.0, macOS 13.0, *) {
            content.formStyle(.grouped)
        } else { content }
    }

    @ViewBuilder func insetGroupedList() -> some View {
        #if os(iOS) || os(visionOS)
        if #available(iOS 14.0, *) { content.listStyle(InsetGroupedListStyle()) }
        else { content.listStyle(GroupedListStyle()) }
        #else
        content
        #endif
    }

    @ViewBuilder func hideScrollBackground() -> some View {
        #if os(tvOS)
        content
        #else
        if #available(iOS 16.0, watchOS 9.0, macOS 13.0, *) {
            content.scrollContentBackground(.hidden)
        } else { content }
        #endif
    }

    @ViewBuilder func dismissKeyboardOnScroll() -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) { content.scrollDismissesKeyboard(.immediately) }
        else { content }
        #else
        content
        #endif
    }
}

struct WawonaProgressView: View {
    private let title: String?
    init(_ title: String? = nil) { self.title = title }
    @ViewBuilder var body: some View {
        if #available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *) {
            if let title { ProgressView(title) } else { ProgressView() }
        } else {
            #if os(iOS)
            VStack(spacing: 8) {
                WawonaActivityIndicator()
                if let title { Text(title) }
            }
            #else
            Text("Working…")
            #endif
        }
    }
}

#if os(iOS)
private struct WawonaActivityIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.startAnimating()
        return view
    }
    func updateUIView(_ view: UIActivityIndicatorView, context: Context) {}
}
#endif

extension WawonaBackport where Content: View {
    @ViewBuilder
    func navigationActions<Leading: View, Trailing: View>(
        trailingIsPrimary: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        if #available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *) {
            content.toolbar {
                ToolbarItem(placement: .cancellationAction) { leading() }
                ToolbarItem(placement: trailingIsPrimary ? .primaryAction : .confirmationAction) { trailing() }
            }
        } else {
            #if os(iOS)
            content.navigationBarItems(leading: leading(), trailing: trailing())
            #else
            content
            #endif
        }
    }

    /// Per-machine Add/Edit sheet chrome. One leading X, one trailing checkmark.
    /// Do **not** use `.cancellationAction` / `.confirmationAction` with custom
    /// SF Symbols on iOS 26: Liquid Glass also vends system close/done there,
    /// which doubles the buttons.
    @ViewBuilder
    @MainActor
    func editorChromeActions(
        saveDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) -> some View {
        if #available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *) {
            #if os(macOS) || os(tvOS)
            content.toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibility(identifier: "wwn.machines.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(saveDisabled)
                        .accessibility(identifier: "wwn.machines.editor.save")
                }
            }
            #elseif os(iOS) || os(visionOS)
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Cancel")
                    .accessibility(identifier: "wwn.machines.editor.cancel")
                }
                if #available(iOS 26.0, visionOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onSave) {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.accentColor)
                        .disabled(saveDisabled)
                        .accessibilityLabel("Save")
                        .accessibility(identifier: "wwn.machines.editor.save")
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onSave) {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                        }
                        .backport.glassProminentToolbarButton()
                        .tint(Color.accentColor)
                        .disabled(saveDisabled)
                        .accessibilityLabel("Save")
                        .accessibility(identifier: "wwn.machines.editor.save")
                    }
                }
            }
            #else
            content
            #endif
        } else {
            #if os(iOS)
            content.navigationBarItems(
                leading: Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel"),
                trailing: Button(action: onSave) {
                    Image(systemName: "checkmark")
                }
                .disabled(saveDisabled)
                .accessibilityLabel("Save")
            )
            #else
            content
            #endif
        }
    }
}

struct WawonaEmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: Text?
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    @ViewBuilder var body: some View {
        if #available(iOS 17.0, tvOS 17.0, watchOS 10.0, macOS 14.0, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: description)
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage).font(.title)
                Text(title).font(.headline)
                description?.foregroundColor(.secondary)
            }.padding().accessibilityElement(children: .combine)
        }
    }
}

struct WawonaDisclosureGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content
    @State private var expanded = false
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    @ViewBuilder var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading) {
            Button(action: { expanded.toggle() }) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                }
            }
            if expanded { content }
        }
        #else
        if #available(iOS 14.0, watchOS 7.0, macOS 11.0, *) {
            DisclosureGroup(title, isExpanded: $expanded) { content }
        } else {
            VStack(alignment: .leading) {
                Button(action: { expanded.toggle() }) {
                    HStack {
                        Text(title)
                        Spacer()
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    }
                }
                if expanded { content }
            }
        }
        #endif
    }
}

extension WawonaBackport where Content: View {
    @ViewBuilder
    func searchable(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            content.searchable(text: text, prompt: Text(prompt))
        } else {
            VStack(spacing: 0) {
                TextField(prompt, text: text).padding().wawonaTextFieldNoAutocaps()
                content
            }
        }
    }

    @ViewBuilder
    func refreshable(_ action: @escaping @MainActor () async -> Void) -> some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            content.refreshable { await action() }
        } else {
            VStack {
                Button("Refresh") { Task { await action() } }
                content
            }
        }
    }
}

// Callers must also expose these actions in their context menu on older hosts.
extension WawonaBackport where Content: View {
    @ViewBuilder
    func supplementarySwipeActions<Actions: View>(@ViewBuilder content actions: () -> Actions) -> some View {
        #if os(tvOS)
        content
        #else
        if #available(iOS 15, macOS 12, watchOS 8, *) {
            content.swipeActions(edge: .trailing, allowsFullSwipe: false, content: actions)
        } else {
            content
        }
        #endif
    }
}


extension WawonaBackport where Content: View {
    func overlay<Overlay: View>(alignment: Alignment = .center,
                                @ViewBuilder content overlay: () -> Overlay) -> some View {
        content.overlay(overlay(), alignment: alignment)
    }

    func background<Background: View>(@ViewBuilder content background: () -> Background) -> some View {
        content.background(background())
    }

    func background<S: Shape>(_ color: Color, in shape: S) -> some View {
        content.background(shape.fill(color))
    }

    @ViewBuilder func animation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            content.animation(animation, value: value)
        } else {
            content.animation(animation)
        }
    }

    @ViewBuilder func editorSheet() -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            if #available(iOS 18.0, *) {
                // Page sizing follows the available window, including multitasking.
                content.presentationSizing(.page).presentationDetents([.large])
            } else if #available(iOS 16.0, *) {
                content.presentationDetents([.large])
            } else {
                content
            }
        } else if #available(iOS 16.4, *) {
            content.presentationDetents([.medium, .large]).presentationContentInteraction(.scrolls)
        } else if #available(iOS 16.0, *) {
            content.presentationDetents([.medium, .large])
        } else { content }
        #else
        content
        #endif
    }

    @ViewBuilder func sidebarList() -> some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
            content.listStyle(SidebarListStyle())
        } else { content.listStyle(DefaultListStyle()) }
        #else
        content
        #endif
    }

    @ViewBuilder func sidebarWidth() -> some View {
        #if os(macOS) || os(iOS)
        if #available(iOS 16.0, macOS 13.0, *) {
            content.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } else { content }
        #else
        content
        #endif
    }

    @ViewBuilder func focused(_ focus: Binding<Bool>) -> some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            content.modifier(WawonaFocus(focus: focus))
        } else { content }
    }
}

@available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
private struct WawonaFocus: ViewModifier {
    @Binding var focus: Bool
    @FocusState private var nativeFocus: Bool
    func body(content: Content) -> some View {
        content.focused($nativeFocus)
            .onAppear { nativeFocus = focus }
            .backport.onChange(of: focus) { nativeFocus = $0 }
            .backport.onChange(of: nativeFocus) { focus = $0 }
    }
}

extension WawonaBackport where Content: View {
    @ViewBuilder func materialBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 15, tvOS 15, watchOS 8, macOS 12, *) {
            content.background(shape.fill(.ultraThinMaterial))
        } else {
            content.background(shape.fill(Color.primary.opacity(0.08)))
        }
    }

    @ViewBuilder func cancelShortcut() -> some View {
        #if !os(tvOS)
        if #available(iOS 14, watchOS 7, macOS 11, *) {
            content.keyboardShortcut(.cancelAction)
        } else { content }
        #else
        content
        #endif
    }

    @ViewBuilder func defaultShortcut() -> some View {
        #if !os(tvOS)
        if #available(iOS 14, watchOS 7, macOS 11, *) {
            content.keyboardShortcut(.defaultAction)
        } else { content }
        #else
        content
        #endif
    }
}

struct WawonaLazyVStack<Content: View>: View {
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    private let content: Content
    init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
         @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    @ViewBuilder var body: some View {
        if #available(iOS 14, tvOS 14, watchOS 7, macOS 11, *) {
            LazyVStack(alignment: alignment, spacing: spacing) { content }
        } else {
            VStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}


extension WawonaBackport where Content: View {
    func accessibilityLabel<S: StringProtocol>(_ text: S) -> some View {
        content.accessibility(label: Text(String(text)))
    }
    func accessibilityHint<S: StringProtocol>(_ text: S) -> some View {
        content.accessibility(hint: Text(String(text)))
    }
}

extension WawonaBackport where Content: View {
    @ViewBuilder func menuPicker() -> some View {
        if #available(iOS 14, tvOS 14, watchOS 7, macOS 11, *) {
            content.pickerStyle(MenuPickerStyle())
        } else { content.pickerStyle(DefaultPickerStyle()) }
    }
    @ViewBuilder func doneSubmitLabel() -> some View {
        if #available(iOS 15, tvOS 15, watchOS 8, macOS 12, *) {
            content.submitLabel(.done)
        } else { content }
    }
}

struct WawonaFittingRow<Horizontal: View, Vertical: View>: View {
    private let horizontal: Horizontal
    private let vertical: Vertical
    init(@ViewBuilder horizontal: () -> Horizontal, @ViewBuilder vertical: () -> Vertical) {
        self.horizontal = horizontal()
        self.vertical = vertical()
    }
    @ViewBuilder var body: some View {
        if #available(iOS 16, tvOS 16, watchOS 9, macOS 13, *) {
            ViewThatFits(in: .horizontal) { horizontal; vertical }
        } else { vertical }
    }
}

#if !os(watchOS)
struct WawonaLink<Label: View>: View {
    let destination: URL
    private let label: Label
    init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }
    @ViewBuilder var body: some View {
        if #available(iOS 14, tvOS 14, macOS 11, *) {
            Link(destination: destination) { label }
        } else {
            Button {
                #if os(iOS)
                UIApplication.shared.open(destination)
                #elseif os(macOS)
                NSWorkspace.shared.open(destination)
                #endif
            } label: { label }
        }
    }
}
#endif


extension WawonaBackport where Content == Any {
    static func compactCount(_ value: UInt64) -> String {
        if #available(iOS 15, tvOS 15, watchOS 8, macOS 12, *) {
            return value.formatted(.number.notation(.compactName))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

extension WawonaBackport where Content: View {
    @ViewBuilder func navigationPicker() -> some View {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if #available(iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            content.pickerStyle(.navigationLink)
        } else { content.pickerStyle(DefaultPickerStyle()) }
        #else
        content.pickerStyle(DefaultPickerStyle())
        #endif
    }
    @ViewBuilder func help(_ text: String) -> some View {
        if #available(iOS 14, tvOS 14, watchOS 7, macOS 11, *) {
            content.help(text)
        } else { content.accessibility(hint: Text(text)) }
    }
}

struct WawonaMenu<Items: View, Label: View>: View {
    private let items: Items
    private let label: Label
    init(@ViewBuilder content: () -> Items, @ViewBuilder label: () -> Label) {
        self.items = content()
        self.label = label()
    }
    @ViewBuilder var body: some View {
        if #available(iOS 14, tvOS 14, watchOS 7, macOS 11, *) {
            Menu { items } label: { label }
        } else {
            Group { label; items }
        }
    }
}
