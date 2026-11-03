import Foundation
import Combine

/// One nested Wayland toplevel shown under Machines "N Tabs" / Tab Overview.
public struct WWNNestedClientTab: Identifiable, Equatable, Hashable {
    public var id: UInt64
    public var title: String
    public var width: UInt32
    public var height: UInt32
    /// 0 = ClientSide, 1 = ServerSide
    public var decorationMode: UInt8
    public var fillsHost: Bool
    /// True when hosted in a floating macOS `WWNWindow` (not Tab Overview).
    public var isStandalone: Bool

    public init(
        id: UInt64,
        title: String,
        width: UInt32,
        height: UInt32,
        decorationMode: UInt8,
        fillsHost: Bool,
        isStandalone: Bool
    ) {
        self.id = id
        self.title = title
        self.width = width
        self.height = height
        self.decorationMode = decorationMode
        self.fillsHost = fillsHost
        self.isStandalone = isStandalone
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Client" : trimmed
    }
}

/// Live nested / standalone Wayland toplevel tabs for Machines sidebar + overview.
@objc(WWNNestedClientTabStore)
public final class WWNNestedClientTabStore: NSObject, ObservableObject {
    @objc public static let shared = WWNNestedClientTabStore()

    public static let didChangeNotification = Notification.Name("WWNNestedClientTabsDidChange")
    public static let pasteboardType = "com.aspauldingcode.wawona.window-id"

    @Published public private(set) var tabs: [WWNNestedClientTab] = []
    @Published public var focusedId: UInt64?
    /// When true, next Created toplevel becomes a floating host window (macOS).
    @Published public var preferStandaloneOnCreate = false
    @Published public var tabsSectionExpanded = true

    /// Nested only (in Tab Overview). Used for sidebar children + overview cards.
    public var nestedTabs: [WWNNestedClientTab] {
        tabs.filter { !$0.isStandalone }
    }

    public var nestedCount: Int { nestedTabs.count }

    public var tabsSectionTitle: String {
        let n = nestedCount
        return n == 1 ? "1 Tab" : "\(n) Tabs"
    }

    /// Show the in-Present session strip only with 2+ nested tabs (Safari rule).
    public var showsSessionTabBar: Bool { nestedCount > 1 }

    private override init() {
        super.init()
    }

    public func upsertCreated(
        id: UInt64,
        title: String,
        width: UInt32,
        height: UInt32,
        decorationMode: UInt8,
        fillsHost: Bool,
        standalone: Bool
    ) {
        let tab = WWNNestedClientTab(
            id: id,
            title: title,
            width: width,
            height: height,
            decorationMode: decorationMode,
            fillsHost: fillsHost,
            isStandalone: standalone
        )
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx] = tab
        } else {
            tabs.append(tab)
        }
        if !standalone {
            focusedId = id
            if nestedCount >= 1 {
                tabsSectionExpanded = true
            }
        }
        notify()
    }

    public func updateTitle(id: UInt64, title: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].title = title
        notify()
    }

    public func updateDecoration(id: UInt64, mode: UInt8) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].decorationMode = mode
        notify()
    }

    public func updateSize(id: UInt64, width: UInt32, height: UInt32) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].width = width
        tabs[idx].height = height
        notify()
    }

    public func remove(id: UInt64) {
        tabs.removeAll { $0.id == id }
        if focusedId == id {
            focusedId = nestedTabs.last?.id
        }
        notify()
    }

    public func markStandalone(id: UInt64, standalone: Bool) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].isStandalone = standalone
        if !standalone {
            focusedId = id
            tabsSectionExpanded = true
        } else if focusedId == id {
            focusedId = nestedTabs.last?.id
        }
        notify()
    }

    public func focus(id: UInt64) {
        guard tabs.contains(where: { $0.id == id && !$0.isStandalone }) else { return }
        focusedId = id
        notify()
    }

    public func clearAll() {
        tabs.removeAll()
        focusedId = nil
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
