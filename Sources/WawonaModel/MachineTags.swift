import Foundation
import Combine

/// Finder-style color tag for machines. Identity is a stable UUID so tag
/// renames keep machine assignments intact.
public struct WWNMachineTag: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var colorHex: String

    /// Finder-style palette: red, orange, yellow, green, mint, teal, blue,
    /// indigo, purple, pink, brown, gray.
    public static let paletteHex = [
        "FF3B30", "FF9500", "FFCC00", "34C759", "00C7A6", "30B0C7",
        "007AFF", "5957D6", "AF52DE", "FF2D55", "A3855E", "8E8E93",
    ]

    public init(id: String, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// Shared store for machine tags + per-machine assignments. Persists to
/// UserDefaults (per app). `WWNCloudSync` mirrors the tag set across Apple
/// hosts through CloudKit and posts `didApplyRemoteChanges` to reload.
public final class WWNMachineTagStore: ObservableObject {
    public static let shared = WWNMachineTagStore()

    @Published public private(set) var tags: [WWNMachineTag] = []
    /// machineId -> tag ids (insertion order preserved).
    @Published public private(set) var tagIdsByMachine: [String: [String]] = [:]

    private let tagsDefaultsKey = "wawona.machines.tags"
    private let assignmentsDefaultsKey = "wawona.machines.tagAssignments"

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: WWNCloudSync.didApplyRemoteChanges, object: nil, queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }

    // MARK: - Reads

    public func tags(for machineId: String) -> [WWNMachineTag] {
        let ids = tagIdsByMachine[machineId] ?? []
        return tags.filter { ids.contains($0.id) }
    }

    public func isAssigned(_ tagId: String, to machineId: String) -> Bool {
        tagIdsByMachine[machineId]?.contains(tagId) ?? false
    }

    // MARK: - Writes

    @discardableResult
    public func createTag(name: String, colorHex: String) -> WWNMachineTag {
        let tag = WWNMachineTag(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex
        )
        guard !tag.name.isEmpty else { return tag }
        tags.append(tag)
        persist()
        return tag
    }

    public func updateTag(_ tag: WWNMachineTag) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[index] = WWNMachineTag(
            id: tag.id,
            name: tag.name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: tag.colorHex
        )
        persist()
    }

    public func deleteTag(id: String) {
        tags.removeAll { $0.id == id }
        for machineId in tagIdsByMachine.keys {
            tagIdsByMachine[machineId]?.removeAll { $0 == id }
        }
        persist()
    }

    public func setAssigned(_ assigned: Bool, tag: WWNMachineTag, to machineId: String) {
        var ids = tagIdsByMachine[machineId] ?? []
        if assigned {
            if !ids.contains(tag.id) {
                ids.append(tag.id)
            }
        } else {
            ids.removeAll { $0 == tag.id }
        }
        if ids.isEmpty {
            tagIdsByMachine.removeValue(forKey: machineId)
        } else {
            tagIdsByMachine[machineId] = ids
        }
        persist()
    }

    /// Drop assignments for machines that no longer exist.
    public func pruneAssignments(keeping machineIds: Set<String>) {
        let stale = tagIdsByMachine.keys.filter { !machineIds.contains($0) }
        guard !stale.isEmpty else { return }
        for machineId in stale {
            tagIdsByMachine.removeValue(forKey: machineId)
        }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: tagsDefaultsKey),
           let decoded = try? JSONDecoder().decode([WWNMachineTag].self, from: data) {
            tags = decoded
        } else if defaults.data(forKey: tagsDefaultsKey) == nil
            && defaults.string(forKey: tagsDefaultsKey) == nil
        {
            tags = Self.templateTags
            persistTagsOnly()
        }
        if let data = defaults.data(forKey: assignmentsDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            tagIdsByMachine = decoded
        }
    }

    /// Work, Personal, Production. Same three templates on every product.
    static let templateTags: [WWNMachineTag] = [
        WWNMachineTag(id: "tag-work", name: "Work", colorHex: "007AFF"),
        WWNMachineTag(id: "tag-personal", name: "Personal", colorHex: "34C759"),
        WWNMachineTag(id: "tag-production", name: "Production", colorHex: "FF3B30"),
    ]

    private func persistTagsOnly() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: tagsDefaultsKey)
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(tags) {
            defaults.set(data, forKey: tagsDefaultsKey)
        }
        if let data = try? JSONEncoder().encode(tagIdsByMachine) {
            defaults.set(data, forKey: assignmentsDefaultsKey)
        }
    }
}

/// Pin persistence shared by every Apple host. Pinned machines lead the
/// Machines list. Hard cap: `maxPinned`.
public final class WWNMachinePinStore: ObservableObject {
    public static let shared = WWNMachinePinStore()
    public static let defaultsKey = "wawona.machines.pinnedMachineIds"
    /// Product limit: at most six pinned machines.
    public static let maxPinned = 6

    @Published public private(set) var pinnedIds: Set<String> = []

    private init() {
        reload()
        NotificationCenter.default.addObserver(
            forName: WWNCloudSync.didApplyRemoteChanges, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    private func reload() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        pinnedIds = Set(stored.prefix(Self.maxPinned))
    }

    public func isPinned(_ machineId: String) -> Bool {
        pinnedIds.contains(machineId)
    }

    public var limitReached: Bool { pinnedIds.count >= Self.maxPinned }

    /// Returns `false` when the pin was refused (already at `maxPinned`).
    @discardableResult
    public func toggle(_ machineId: String) -> Bool {
        if pinnedIds.remove(machineId) == nil {
            guard !limitReached else { return false }
            pinnedIds.insert(machineId)
        }
        persist()
        return true
    }

    public func prune(keeping machineIds: Set<String>) {
        let kept = pinnedIds.intersection(machineIds)
        guard kept != pinnedIds else { return }
        pinnedIds = kept
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(pinnedIds), forKey: Self.defaultsKey)
    }
}
