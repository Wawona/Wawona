#if os(watchOS)
import SwiftUI

/// Bottom-leading search control. Collapsed it is the system circular toolbar
/// button. Expanded it grows rightward into a capsule that shows "Search" or
/// the current query. A tap edits the query in the keyboard with that text
/// (no autocorrect, no capitalization).
struct WatchSearchPillButton: View {
    @Binding var query: String
    var expanded: Bool
    var expandedWidth: CGFloat
    var onTap: () -> Void
    var onIconWidth: (CGFloat) -> Void = { _ in }
    var onCollapsedWidth: (CGFloat) -> Void = { _ in }

    /// Natural icon-only label width. Width animates between two numbers so
    /// the capsule grows rightward from a fixed leading edge.
    @State private var iconWidth: CGFloat?
    /// Icon x inside the collapsed circle, where the system centers it.
    @State private var restingIconX: CGFloat = 0
    /// Label leading x inside the expanded capsule (the button's own inset).
    @State private var expandedLabelX: CGFloat?

    private static let space = "wwn.watch.search.pill"

    /// Keeps the magnifying glass at its collapsed x while the capsule grows.
    private var iconInset: CGFloat {
        guard expanded, let expandedLabelX else { return 0 }
        return max(0, restingIconX - expandedLabelX)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        if iconWidth == nil {
                            iconWidth = width
                            onIconWidth(width)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named(Self.space)).minX
                    } action: { x in
                        if !expanded { restingIconX = x }
                    }
                if expanded {
                    Text(query.isEmpty ? "Search" : query)
                        .foregroundStyle(query.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(.leading, iconInset)
            .frame(width: expanded ? expandedWidth : iconWidth, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .named(Self.space)).minX
            } action: { x in
                if expanded { expandedLabelX = x }
            }
        }
        .buttonBorderShape(.capsule)
        // The expanded capsule is drawn by the Button but must not take the
        // tap, or it swallows it before the TextField below sees it.
        .allowsHitTesting(!expanded)
        .overlay {
            if expanded {
                // Tap target only, laid over the capsule. The watch TextField
                // opens the keyboard with the current text. Its own platter
                // stays invisible.
                TextField("Search", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.02)
                    .accessibilityIdentifier("wwn.watch.search.field")
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if !expanded { onCollapsedWidth(width) }
        }
        .animation(WatchSearchInput.animation, value: expanded)
        .animation(WatchSearchInput.animation, value: query)
        .accessibilityLabel(query.isEmpty ? "Search" : "Search, \(query)")
        .accessibilityIdentifier("wwn.watch.search")
    }
}

/// Bottom toolbar row. One toolbar item with a fixed-width row, so the search
/// control's leading edge is pinned by this layout, not by the bar, which
/// re-centers its items when one of them changes width.
struct WatchSearchBottomBar: View {
    @Binding var query: String
    var searching: Bool
    var rowWidth: CGFloat
    var addLabel: String
    var addIdentifier: String
    var onSearch: () -> Void
    var onAdd: () -> Void
    var onCancel: () -> Void

    @State private var collapsedWidth: CGFloat = 0
    @State private var iconWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0

    private static let gap: CGFloat = 6
    private static let space = "wwn.watch.search.row"

    /// Label width that makes the capsule end one gap before the trailing button.
    private var expandedLabelWidth: CGFloat {
        let chrome = max(0, collapsedWidth - iconWidth)
        return max(iconWidth, rowWidth - trailingWidth - Self.gap - chrome)
    }

    var body: some View {
        HStack(spacing: 0) {
            WatchSearchPillButton(
                query: $query,
                expanded: searching,
                expandedWidth: expandedLabelWidth,
                onTap: onSearch,
                onIconWidth: { iconWidth = $0 },
                onCollapsedWidth: { collapsedWidth = $0 }
            )
            Spacer(minLength: Self.gap)
                .allowsHitTesting(false)
            WatchSearchTrailingButton(
                searching: searching,
                addLabel: addLabel,
                addIdentifier: addIdentifier,
                onAdd: onAdd,
                onCancel: onCancel
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                trailingWidth = width
            }
        }
        .frame(width: rowWidth)
        .coordinateSpace(.named(Self.space))
        // No contentShape over the row. A shape around both platters hit-tests
        // as their bounding box, which is the expanded pill, and that box
        // steals taps from machine rows at this height.
    }
}

/// Top toolbar control that fades and shrinks away while search is open.
/// The item stays in the toolbar so the bar does not relayout instantly.
/// The control draws its own platter: the system platter ignores the item's
/// opacity and would pop out when the item is removed.
struct WatchSearchHiddenWhileSearching: ViewModifier {
    var searching: Bool

    func body(content: Content) -> some View {
        content
            .buttonStyle(WatchSearchBarButtonStyle())
            .opacity(searching ? 0 : 1)
            .scaleEffect(searching ? 0.6 : 1)
            .allowsHitTesting(!searching)
            .accessibilityHidden(searching)
            .animation(WatchSearchInput.animation, value: searching)
    }
}

/// Circular top-bar button whose platter fades with the button.
struct WatchSearchBarButtonStyle: ButtonStyle {
    static let diameter: CGFloat = 35

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(width: Self.diameter, height: Self.diameter)
            .modifier(WatchSearchBarPlatter())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private struct WatchSearchBarPlatter: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(Circle().fill(Color.white.opacity(0.16)))
        }
    }
}

/// Lifts the list into the title row while search is open. The bar keeps
/// that row's safe area after the title and buttons fade, which leaves a
/// blank band. Pull the list up by the unused part of that band. The clock
/// row stays: this never ignores the top safe area.
struct WatchSearchLift: ViewModifier {
    var active: Bool
    /// Top inset at rest: clock plus the title row.
    @State private var restingInset: CGFloat = 0
    /// Top inset right now. Drops if the bar actually gives the title row back.
    @State private var liveInset: CGFloat = 0

    /// Title-and-buttons row under the clock. Matches the top bar button.
    private static let titleBand: CGFloat = WatchSearchBarButtonStyle.diameter + 6

    /// How far to pull the list up. If the system already shrank the inset,
    /// only the leftover gap moves.
    private var lift: CGFloat {
        guard active else { return 0 }
        let dropped = max(0, restingInset - liveInset)
        return max(0, Self.titleBand - dropped)
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, -lift)
            .animation(WatchSearchInput.animation, value: lift)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { inset in
                liveInset = inset
                if !active {
                    restingInset = max(restingInset, inset)
                }
            }
            .watchNavigationBarChrome(cleared: active)
    }
}

extension View {
    /// Native bar material at rest. Search hides that material and the
    /// scroll-edge blur so the raised list can reach the top safe area.
    @ViewBuilder
    func watchNavigationBarChrome(cleared: Bool) -> some View {
        if #available(watchOS 26.0, *) {
            toolbarBackgroundVisibility(cleared ? .hidden : .automatic, for: .navigationBar)
                .scrollEdgeEffectHidden(cleared, for: .top)
        } else if #available(watchOS 11.0, *) {
            toolbarBackgroundVisibility(cleared ? .hidden : .automatic, for: .navigationBar)
        } else {
            toolbarBackground(cleared ? .hidden : .automatic, for: .navigationBar)
        }
    }
}

/// Bottom-trailing control. Plus (blue) when idle, plain xmark while searching.
/// Same button, same slot. Only the symbol and tint change.
struct WatchSearchTrailingButton: View {
    var searching: Bool
    var addLabel: String
    var addIdentifier: String
    var onAdd: () -> Void
    var onCancel: () -> Void

    var body: some View {
        Button(action: searching ? onCancel : onAdd) {
            Image(systemName: searching ? "xmark" : "plus")
                .foregroundStyle(searching ? Color.primary : Color.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonBorderShape(.circle)
        .tint(searching ? nil : Color.blue)
        .animation(WatchSearchInput.animation, value: searching)
        .accessibilityLabel(searching ? "Cancel Search" : addLabel)
        .accessibilityIdentifier(searching ? "wwn.watch.search.cancel" : addIdentifier)
    }
}

enum WatchSearchInput {
    static let expandDuration: Double = 0.35
    static let animation: Animation = .smooth(duration: expandDuration)
}

struct WatchContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum WatchSearchHighlight {
    /// Pastel mark on matched characters. Same treatment as iOS machine cards.
    static func name(_ name: String, query: String, scheme: ColorScheme) -> AttributedString {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return AttributedString(name) }
        let highlight = scheme == .dark
            ? Color(red: 0.93, green: 0.78, blue: 0.28).opacity(0.50)
            : Color(red: 1.0, green: 0.94, blue: 0.55).opacity(0.82)
        let ink = Color(red: 0.12, green: 0.12, blue: 0.12)
        var attributed = AttributedString()
        var needleIndex = 0
        for character in name {
            var piece = AttributedString(String(character))
            if needleIndex < needle.count,
               String(character).lowercased() == String(needle[needleIndex]) {
                piece.backgroundColor = highlight
                piece.foregroundColor = ink
                piece.inlinePresentationIntent = .stronglyEmphasized
                needleIndex += 1
            }
            attributed.append(piece)
        }
        return attributed
    }
}
#endif
