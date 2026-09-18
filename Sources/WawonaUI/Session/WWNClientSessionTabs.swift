#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
import SwiftUI
import UIKit

// MARK: - Tab Item Model (Rootshell TabModel ported to Wawona)

/// One Wayland client toplevel represented as a tab.
@objc(WWNClientTabItem)
public final class WWNClientTabItem: NSObject, Identifiable, ObservableObject {
    @objc public var id: UInt64
    @objc public var title: String
    @objc public var preview: UIImage?

    @objc public init(id: UInt64, title: String, preview: UIImage? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        return hasher.finalize()
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? WWNClientTabItem else { return false }
        return id == other.id
    }

    public var segmentedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Client"
        }
        let lower = trimmed.lowercased()
        if lower.contains("terminal") {
            return "Terminal"
        }
        if lower.contains("niri") {
            return "Niri"
        }
        if lower.contains("weston") {
            return "Weston"
        }
        if lower.contains("foot") {
            return "Foot"
        }
        if lower.contains("kmscube") || lower.contains("cube") {
            return "Cube"
        }
        if lower.contains("wasm") {
            return "Wasm"
        }
        if lower.contains("bash") || lower.contains("zsh") || lower.contains("sh") {
            return "Shell"
        }
        return trimmed.capitalized
    }
}

// MARK: - Tabs Model (Rootshell TabsModel ported to Wawona)

final class WWNClientTabChromeModel: ObservableObject {
    @Published var tabs: [WWNClientTabItem] = []
    @Published var selectedId: UInt64 = 0
    @Published var overviewOpen = false
    @Published var hoveredTabId: UInt64? = nil

    var onSelect: ((UInt64) -> Void)?
    var onClose: ((UInt64) -> Void)?
    var onNewTab: (() -> Void)?
    var onRequestRefreshPreviews: (() -> Void)?

    func toggleExpose() {
        overviewOpen.toggle()
        if overviewOpen {
            onRequestRefreshPreviews?()
        }
    }

    var selectedIndex: Int {
        tabs.firstIndex(where: { $0.id == selectedId }) ?? 0
    }

    func select(_ id: UInt64) {
        guard selectedId != id else {
            overviewOpen = false
            return
        }
        selectedId = id
        overviewOpen = false
        onSelect?(id)
    }

    func close(_ id: UInt64) {
        onClose?(id)
    }

    func closeOthers(except id: UInt64) {
        let targets = tabs.filter { $0.id != id }.map(\.id)
        for target in targets {
            close(target)
        }
    }

    func createNewTab() {
        overviewOpen = false
        onNewTab?()
    }

    func selectNext() {
        guard !tabs.isEmpty else { return }
        if let idx = tabs.firstIndex(where: { $0.id == selectedId }) {
            let nextIdx = (idx + 1) % tabs.count
            select(tabs[nextIdx].id)
        } else if let first = tabs.first {
            select(first.id)
        }
    }

    func selectPrevious() {
        guard !tabs.isEmpty else { return }
        if let idx = tabs.firstIndex(where: { $0.id == selectedId }) {
            let prevIdx = (idx - 1 + tabs.count) % tabs.count
            select(tabs[prevIdx].id)
        } else if let last = tabs.last {
            select(last.id)
        }
    }

    func selectIndex(_ index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        select(tabs[index].id)
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabs.indices.contains(sourceIndex),
              tabs.indices.contains(destinationIndex) else { return }
        let item = tabs.remove(at: sourceIndex)
        tabs.insert(item, at: destinationIndex)
    }
}

// MARK: - Content-Aware Tab Sizing Policy (Rootshell TabBarSizingPolicy ported)

enum WWNTabBarDisplayMode: Equatable {
    case singleTab
    case segmented
    case equalWidth
    case scrolling
}

struct WWNTabBarSizingDecision: Equatable {
    let mode: WWNTabBarDisplayMode
    let equalTabWidth: CGFloat
    let singleTabWidth: CGFloat
    let scrollingTabWidth: CGFloat
}

enum WWNTabBarSizingPolicy {
    static let minimumFloorWidth: CGFloat = 140
    static let integratedMaximumWidth: CGFloat = 240
    static let scrollingMaximumWidth: CGFloat = 200
    static let actionButtonsWidth: CGFloat = 96 // + button and expose button combined
    static let barHeight: CGFloat = 44

    static func maxSegmentCount(for availableWidth: CGFloat) -> Int {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return availableWidth > 600 ? 7 : 5
        }
        return 5
        #else
        return availableWidth > 600 ? 7 : 5
        #endif
    }

    static func decision(availableWidth: CGFloat, count: Int) -> WWNTabBarSizingDecision {
        guard count > 0 else {
            return WWNTabBarSizingDecision(
                mode: .singleTab,
                equalTabWidth: 0,
                singleTabWidth: 0,
                scrollingTabWidth: 0
            )
        }

        let usableWidth = max(0, availableWidth - actionButtonsWidth)

        if count == 1 {
            let defaultWidth = usableWidth * 0.70
            let width = min(usableWidth, max(minimumFloorWidth, defaultWidth))
            return WWNTabBarSizingDecision(
                mode: .singleTab,
                equalTabWidth: width,
                singleTabWidth: width,
                scrollingTabWidth: width
            )
        }

        let maxSegments = maxSegmentCount(for: usableWidth)
        if count >= 2 && count <= maxSegments {
            return WWNTabBarSizingDecision(
                mode: .segmented,
                equalTabWidth: usableWidth / CGFloat(count),
                singleTabWidth: 0,
                scrollingTabWidth: 0
            )
        }

        let spacing: CGFloat = 4
        let totalSpacing = CGFloat(count - 1) * spacing
        let equalAvailableWidth = max(0, usableWidth - totalSpacing)
        let equalWidth = equalAvailableWidth / CGFloat(count)

        if equalWidth >= minimumFloorWidth {
            let resolved = min(integratedMaximumWidth, equalWidth)
            return WWNTabBarSizingDecision(
                mode: .equalWidth,
                equalTabWidth: resolved,
                singleTabWidth: 0,
                scrollingTabWidth: resolved
            )
        }

        let scrollWidth = min(scrollingMaximumWidth, max(minimumFloorWidth, equalWidth))
        return WWNTabBarSizingDecision(
            mode: .scrolling,
            equalTabWidth: 0,
            singleTabWidth: 0,
            scrollingTabWidth: scrollWidth
        )
    }
}

// MARK: - Pass-Through Container View

/// Pass-through plate: empty areas return nil so underlying compositor / Mode B HID
/// get touch and pointer events. Interactive SwiftUI controls still receive hits.
final class WWNClientTabPassThroughView: UIView {
    weak var controller: WWNClientTabChromeController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else {
            return nil
        }
        if hit === self {
            return nil
        }
        if let ctrl = controller, !ctrl.isOverviewOpen {
            let maxBarY = safeAreaInsets.top + WWNTabBarSizingPolicy.barHeight + 16
            if point.y > maxBarY {
                return nil
            }
        }
        return hit
    }
}

/// Full-screen host: only interactive descendants receive hits.
final class WWNClientTabHostingController: UIHostingController<WWNClientSessionTabBarRootView> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }
}

// MARK: - Root Tab View

struct WWNClientSessionTabBarRootView: View {
    @ObservedObject var model: WWNClientTabChromeModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .allowsHitTesting(false)

            if !model.tabs.isEmpty && !model.overviewOpen {
                WWNClientTabBar(model: model)
                    .padding(.top, topSafeAreaInset)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.overviewOpen {
                WWNClientTabExposeView(model: model)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .accessibilityIdentifier("wwn.client.tabs")
    }

    private var topSafeAreaInset: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 4
        #endif
    }
}

// MARK: - Liquid Glass Tab Components (Rootshell 1:1 GlassedCapsule & TroughWell)

/// Rootshell GlassedCapsule: Liquid Glass appearance with ultra-thin material,
/// tint overlay, light refraction specular gradient, hairline border, and drop shadow.
struct WWNGlassedCapsule: View {
    let tintColor: Color
    var isLightTheme: Bool = false

    var body: some View {
        Capsule()
            // Base blur material
            .fill(.ultraThinMaterial)
            // Tint overlay
            .overlay(
                Capsule()
                    .fill(tintColor.opacity(0.35))
            )
            // Light refraction gradient
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(isLightTheme ? 0.35 : 0.22),
                                .white.opacity(isLightTheme ? 0.12 : 0.06),
                                .clear,
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            // Edge stroke for definition
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isLightTheme ? 0.55 : 0.35),
                                .white.opacity(isLightTheme ? 0.20 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            // Drop shadow for depth
            .shadow(
                color: .black.opacity(isLightTheme ? 0.15 : 0.30),
                radius: 8,
                x: 0,
                y: 4
            )
    }
}

/// Rootshell TroughWellBackground: Segmented-control track behind the tab run.
struct WWNTroughWellBackground: View {
    let segmentCount: Int
    let selectedSegment: Int?
    let segmentWidth: CGFloat

    private var hairline: Color {
        Color.primary.opacity(0.12)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(uiColor: .tertiarySystemBackground).opacity(0.60))
                .overlay(Capsule().strokeBorder(hairline, lineWidth: 0.5))

            ForEach(1..<max(segmentCount, 1), id: \.self) { index in
                let touchesKnob = selectedSegment.map { index == $0 || index == $0 + 1 } ?? false
                Rectangle()
                    .fill(hairline)
                    .frame(width: 0.5, height: 16)
                    .offset(x: CGFloat(index) * segmentWidth - 0.25)
                    .opacity(touchesKnob ? 0 : 1)
            }
        }
        .frame(height: 32)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Top Tab Bar View (Rootshell TabBar.swift ported to Wawona)

struct WWNClientTabBar: View {
    @ObservedObject var model: WWNClientTabChromeModel
    @Namespace private var tabAnimationNamespace

    var body: some View {
        GeometryReader { geometry in
            let decision = WWNTabBarSizingPolicy.decision(
                availableWidth: geometry.size.width,
                count: model.tabs.count
            )

            HStack(spacing: 4) {
                // Leading Add Tab Button (+)
                addButton

                // Tab View Content (Single, Equal Width, or Scrolling)
                tabTrack(decision: decision)
                    .frame(maxWidth: .infinity)

                // Trailing Exposé Overview Button (square.on.square)
                exposeButton
            }
            .padding(.horizontal, 8)
            .frame(height: WWNTabBarSizingPolicy.barHeight)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.black.opacity(0.20))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.30),
                                        Color.white.opacity(0.10),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 10)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.selectedId)
        }
        .frame(height: WWNTabBarSizingPolicy.barHeight)
    }

    // MARK: - Add Tab Button

    private var addButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                model.createNewTab()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Tab")
        .accessibilityIdentifier("wwn.client.tab.new")
    }

    // MARK: - Exposé Toggle Button

    private var exposeButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                model.toggleExpose()
            }
        } label: {
            ZStack {
                Image(systemName: "square.on.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if model.tabs.count > 1 {
                    Text("\(model.tabs.count)")
                        .font(.system(size: 9, weight: .bold))
                        .offset(y: 0.5)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(model.overviewOpen ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08))
                    .overlay(
                        Circle().strokeBorder(
                            model.overviewOpen ? Color.accentColor : Color.white.opacity(0.20),
                            lineWidth: 0.5
                        )
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tab Overview")
        .accessibilityIdentifier("wwn.client.tabs.overview")
    }

    // MARK: - Tab Track Content

    @ViewBuilder
    private func tabTrack(decision: WWNTabBarSizingDecision) -> some View {
        switch decision.mode {
        case .singleTab:
            if let tab = model.tabs.first {
                singleTabView(tab: tab, width: decision.singleTabWidth)
            }
        case .segmented:
            segmentedControlView
        case .equalWidth:
            equalWidthView(width: decision.equalTabWidth)
        case .scrolling:
            scrollingView(tabWidth: decision.scrollingTabWidth)
        }
    }

    // MARK: - Segmented Control Layout (Rootshell tab support with HIG Segmented Control)

    private var segmentedControlView: some View {
        Picker(
            "Client Tabs",
            selection: Binding(
                get: { model.selectedId },
                set: { model.select($0) }
            )
        ) {
            ForEach(model.tabs) { tab in
                Text(tab.segmentedTitle)
                    .tag(tab.id)
            }
        }
        .pickerStyle(.segmented)
        .contextMenu {
            if let activeTab = model.tabs.first(where: { $0.id == model.selectedId }) {
                Button(role: .destructive) {
                    model.close(activeTab.id)
                } label: {
                    Label("Close \(activeTab.segmentedTitle)", systemImage: "xmark")
                }
            }
            if model.tabs.count > 1 {
                Button {
                    model.closeOthers(except: model.selectedId)
                } label: {
                    Label("Close Other Tabs", systemImage: "xmark.circle")
                }
            }
            Divider()
            Button {
                model.toggleExpose()
            } label: {
                Label("Tab Overview", systemImage: "square.on.square")
            }
        }
        .accessibilityIdentifier("wwn.client.tabs.segmented")
    }

    // MARK: - Single Tab Layout

    private func singleTabView(tab: WWNClientTabItem, width: CGFloat) -> some View {
        HStack {
            Spacer(minLength: 0)
            WWNClientTabItemView(
                tab: tab,
                index: 0,
                isSelected: tab.id == model.selectedId,
                width: width,
                namespace: tabAnimationNamespace,
                onSelect: { model.select(tab.id) },
                onClose: { model.close(tab.id) },
                onMoveLeft: nil,
                onMoveRight: nil,
                onCloseOthers: { model.closeOthers(except: tab.id) },
                onToggleExpose: { model.toggleExpose() }
            )
            .frame(width: width)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Equal Width Layout

    private func equalWidthView(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                let moveLeft = index > 0 ? { model.moveTab(from: index, to: index - 1) } : nil
                let moveRight = index < model.tabs.count - 1 ? { model.moveTab(from: index, to: index + 1) } : nil

                WWNClientTabItemView(
                    tab: tab,
                    index: index,
                    isSelected: tab.id == model.selectedId,
                    width: width,
                    namespace: tabAnimationNamespace,
                    onSelect: { model.select(tab.id) },
                    onClose: { model.close(tab.id) },
                    onMoveLeft: moveLeft,
                    onMoveRight: moveRight,
                    onCloseOthers: { model.closeOthers(except: tab.id) },
                    onToggleExpose: { model.toggleExpose() }
                )
                .frame(width: width)
            }
        }
        .background {
            WWNTroughWellBackground(
                segmentCount: model.tabs.count,
                selectedSegment: model.tabs.firstIndex(where: { $0.id == model.selectedId }),
                segmentWidth: width + 4
            )
        }
    }

    // MARK: - Scrolling Layout

    private func scrollingView(tabWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                        let moveLeft = index > 0 ? { model.moveTab(from: index, to: index - 1) } : nil
                        let moveRight = index < model.tabs.count - 1 ? { model.moveTab(from: index, to: index + 1) } : nil

                        WWNClientTabItemView(
                            tab: tab,
                            index: index,
                            isSelected: tab.id == model.selectedId,
                            width: tabWidth,
                            namespace: tabAnimationNamespace,
                            onSelect: { model.select(tab.id) },
                            onClose: { model.close(tab.id) },
                            onMoveLeft: moveLeft,
                            onMoveRight: moveRight,
                            onCloseOthers: { model.closeOthers(except: tab.id) },
                            onToggleExpose: { model.toggleExpose() }
                        )
                        .frame(width: tabWidth)
                        .id(tab.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: model.selectedId) { newId in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Tab Item Pill (Rootshell TabButton ported to Wawona)

struct WWNClientTabItemView: View {
    let tab: WWNClientTabItem
    let index: Int
    let isSelected: Bool
    let width: CGFloat
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void
    let onMoveLeft: (() -> Void)?
    let onMoveRight: (() -> Void)?
    let onCloseOthers: () -> Void
    let onToggleExpose: () -> Void

    private var titleText: String {
        tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Client"
            : tab.title
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Shortcut badge (⌘1 - ⌘9)
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.85) : Color.secondary)
                }

                // Title
                Text(titleText)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Close Button (xmark)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.85) : Color.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Close \(titleText)")
                .accessibilityIdentifier("wwn.client.tab.close.\(tab.id)")
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if isSelected {
                    WWNGlassedCapsule(tintColor: Color.accentColor)
                        .matchedGeometryEffect(id: "selectedTabKnob", in: namespace)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.03))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onMoveLeft {
                Button {
                    onMoveLeft()
                } label: {
                    Label("Move Left", systemImage: "arrow.left")
                }
            }
            if let onMoveRight {
                Button {
                    onMoveRight()
                } label: {
                    Label("Move Right", systemImage: "arrow.right")
                }
            }
            Divider()
            Button {
                onCloseOthers()
            } label: {
                Label("Close Other Tabs", systemImage: "xmark.circle")
            }
            Button {
                onToggleExpose()
            } label: {
                Label("Exposé Overview", systemImage: "square.on.square")
            }
            Divider()
            Button(role: .destructive, action: onClose) {
                Label("Close Tab", systemImage: "xmark")
            }
        }
        .accessibilityIdentifier("wwn.client.tab.\(tab.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Tab Exposé Grid View (Safari iOS tabs overview style)

struct WWNClientTabExposeView: View {
    @ObservedObject var model: WWNClientTabChromeModel

    private var columns: [GridItem] {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [
                GridItem(.flexible(), spacing: 18),
                GridItem(.flexible(), spacing: 18),
                GridItem(.flexible(), spacing: 18)
            ]
        }
        #endif
        return [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
    }

    private var tabCountString: String {
        model.tabs.count == 1 ? "1 Tab" : "\(model.tabs.count) Tabs"
    }

    var body: some View {
        ZStack {
            // Safari dark blurred backdrop; tap dismisses overview
            Color.black.opacity(0.85)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        model.overviewOpen = false
                    }
                }

            VStack(spacing: 0) {
                // Safari Top Header Strip
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 16, weight: .semibold))
                        Text(tabCountString)
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            model.overviewOpen = false
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.primary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 12)

                // Safari 2-Column Tabs Grid
                ScrollView(showsIndicators: true) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                            WWNClientTabExposeCard(
                                tab: tab,
                                index: index,
                                isSelected: tab.id == model.selectedId,
                                onSelect: {
                                    model.select(tab.id)
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                        model.overviewOpen = false
                                    }
                                },
                                onClose: {
                                    model.close(tab.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
            }

            // Safari Floating Bottom Toolbar
            VStack {
                Spacer()

                HStack {
                    // New Tab Button (+)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            model.createNewTab()
                            model.overviewOpen = false
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Tab")

                    Spacer()

                    // Center Tab Counter
                    Text(tabCountString)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Trailing Done Button
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            model.overviewOpen = false
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .accessibilityIdentifier("wwn.client.tabs.expose")
    }
}

// MARK: - Exposé Card View (Safari iOS card with accurate Wayland aspect ratio)

struct WWNClientTabExposeCard: View {
    let tab: WWNClientTabItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    private var titleText: String {
        tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Client"
            : tab.title
    }

    private var iconName: String {
        let lower = titleText.lowercased()
        if lower.contains("term") || lower.contains("zsh") || lower.contains("sh") || lower.contains("nvim") || lower.contains("vim") {
            return "terminal.fill"
        }
        return "macwindow"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Safari Card Header Strip
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(titleText)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(titleText)")
                .accessibilityIdentifier("wwn.client.tab.close.\(tab.id)")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Live Wayland Client Preview Frame (Safari aspect ratio, true buffer mapping)
            ZStack {
                Color.black

                if let preview = tab.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: iconName)
                            .font(.system(size: 28))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                        Text(titleText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.60, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 2.5 : 0.8
                        )
                )
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.35),
                    radius: isSelected ? 10 : 6,
                    x: 0,
                    y: 4
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityIdentifier("wwn.client.tab.\(tab.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Objective-C Host Controller (WWNClientTabChromeController)

/// ObjC host for SceneDelegate. Full-screen pass-through; bar + overview
/// receive hits. Underlying compositor keeps the rest.
@objc(WWNClientTabChromeController)
public final class WWNClientTabChromeController: NSObject {
    private let model = WWNClientTabChromeModel()
    private var host: WWNClientTabHostingController?
    private var passThrough: WWNClientTabPassThroughView?

    @objc public var onSelectId: ((UInt64) -> Void)?
    @objc public var onCloseId: ((UInt64) -> Void)?
    @objc public var onNewTab: (() -> Void)?
    @objc public var onRequestRefreshPreviews: (() -> Void)?

    @objc public var hostView: UIView? { passThrough ?? host?.view }
    var hostingView: UIView? { host?.view }
    @objc public var isOverviewOpen: Bool {
        get { model.overviewOpen }
        set { model.overviewOpen = newValue }
    }

    @objc public func attach(to parentView: UIView) {
        if let existing = passThrough {
            if existing.superview !== parentView {
                existing.removeFromSuperview()
                parentView.addSubview(existing)
                NSLayoutConstraint.activate([
                    existing.topAnchor.constraint(equalTo: parentView.topAnchor),
                    existing.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                    existing.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                    existing.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
                ])
            }
            parentView.bringSubviewToFront(existing)
            return
        }

        model.onSelect = { [weak self] id in self?.onSelectId?(id) }
        model.onClose = { [weak self] id in self?.onCloseId?(id) }
        model.onNewTab = { [weak self] in self?.onNewTab?() }
        model.onRequestRefreshPreviews = { [weak self] in self?.onRequestRefreshPreviews?() }

        let hc = WWNClientTabHostingController(rootView: WWNClientSessionTabBarRootView(model: model))
        hc.view.backgroundColor = .clear
        hc.view.isOpaque = false
        hc.view.clipsToBounds = false
        hc.view.isUserInteractionEnabled = true
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        let plate = WWNClientTabPassThroughView()
        plate.controller = self
        plate.backgroundColor = .clear
        plate.isOpaque = false
        plate.clipsToBounds = false
        plate.isUserInteractionEnabled = true
        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(hc.view)

        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: plate.topAnchor),
            hc.view.leadingAnchor.constraint(equalTo: plate.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: plate.trailingAnchor),
            hc.view.bottomAnchor.constraint(equalTo: plate.bottomAnchor),
        ])

        parentView.addSubview(plate)
        NSLayoutConstraint.activate([
            plate.topAnchor.constraint(equalTo: parentView.topAnchor),
            plate.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            plate.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
        ])

        host = hc
        passThrough = plate
    }

    @objc public func setHidden(_ hidden: Bool) {
        if hidden {
            model.overviewOpen = false
        }
        passThrough?.isHidden = hidden
        host?.view.isHidden = hidden
    }

    @objc public var isAttached: Bool { passThrough != nil || host != nil }

    @objc public var selectedId: UInt64 { model.selectedId }

    @objc public func selectNextTab() {
        model.selectNext()
    }

    @objc public func selectPreviousTab() {
        model.selectPrevious()
    }

    @objc public func selectTab(at index: Int) {
        model.selectIndex(index)
    }

    @objc public func toggleTabExpose() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.toggleExpose()
        }
    }

    @objc public func createNewTab() {
        model.createNewTab()
    }

    @objc public func reload(
        ids: [NSNumber],
        titles: [String],
        selectedId: NSNumber
    ) {
        reload(ids: ids, titles: titles, selectedId: selectedId, previewImages: [:])
    }

    @objc public func reload(
        ids: [NSNumber],
        titles: [String],
        selectedId: NSNumber,
        previewImages: [NSNumber: UIImage]
    ) {
        var previous: [UInt64: UIImage] = [:]
        for tab in model.tabs {
            if let img = tab.preview {
                previous[tab.id] = img
            }
        }

        var items: [WWNClientTabItem] = []
        items.reserveCapacity(ids.count)
        for (index, idNum) in ids.enumerated() {
            let title = index < titles.count ? titles[index] : "Untitled"
            let preview = previewImages[idNum] ?? previous[idNum.uint64Value]
            items.append(WWNClientTabItem(id: idNum.uint64Value, title: title, preview: preview))
        }

        model.tabs = items
        model.selectedId = selectedId.uint64Value
        if items.isEmpty {
            model.overviewOpen = false
        }

        if let plate = passThrough {
            plate.superview?.bringSubviewToFront(plate)
        } else if let view = host?.view {
            view.superview?.bringSubviewToFront(view)
        }
    }
}
#endif
