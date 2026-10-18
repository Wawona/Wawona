import CloudKit
import Foundation

/// One fetch, apply, push round against the private database zone.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
struct CloudSyncPass {
    enum Outcome {
        case synced(homeFiles: Int, limitReached: Bool)
        case unavailable(String)
        case failed(String)
    }

    private static let zoneID = CKRecordZone.ID(zoneName: "WawonaSync", ownerName: CKCurrentUserDefaultName)
    private static let subscriptionID = "wawona-private-changes"
    private static let defaultType = "WawonaDefault"
    private static let homeType = "WawonaHomeFile"
    private static let batchSize = 100

    let owner: WWNCloudSync
    private let database = CKContainer(identifier: WWNCloudSync.containerIdentifier).privateCloudDatabase
    private let container = CKContainer(identifier: WWNCloudSync.containerIdentifier)

    init(owner: WWNCloudSync) {
        self.owner = owner
    }

    func run() async -> Outcome {
        if let why = await accountProblem() { return .unavailable(why) }
        var state = CloudSyncState.load()
        var retried = false
        while true {
            do {
                let outcome = try await round(&state)
                state.save()
                return outcome
            } catch let error as CKError where !retried {
                retried = true
                switch error.code {
                case .changeTokenExpired:
                    state.changeToken = nil
                    continue
                case .zoneNotFound, .userDeletedZone:
                    state.forgetServer()
                    continue
                default:
                    state.save()
                    return Self.describe(error)
                }
            } catch {
                state.save()
                return Self.describe(error)
            }
        }
    }

    private func round(_ state: inout CloudSyncState) async throws -> Outcome {
        let root = URL(fileURLWithPath: owner.homePath()).resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scan = scanLocal(&state, root: root)

        if !state.zoneReady {
            _ = try await database.save(CKRecordZone(zoneID: Self.zoneID))
            state.zoneReady = true
        }
        if !state.subscriptionReady {
            let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            if (try? await database.save(subscription)) != nil {
                state.subscriptionReady = true
            }
        }

        let applied = try await fetch(&state, root: root)
        let pushFailures = try await push(&state, root: root)
        if applied { owner.announceRemoteChanges() }
        if pushFailures > 0 {
            return .failed("\(pushFailures) item(s) did not upload; will retry")
        }
        let files = state.home.values.filter { $0.hash != CloudSyncState.deletedHash }.count
        return .synced(homeFiles: files, limitReached: scan.limitReached)
    }

    // MARK: Local

    private func scanLocal(_ state: inout CloudSyncState, root: URL) -> CloudSyncHome.Scan {
        let now = Date()
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where CloudSyncPolicy.isSyncedDefaultsKey(key)
        {
            guard let payload = CloudSyncDefaults.payload(for: key) else { continue }
            let hash = CloudSyncState.digest(payload)
            if state.defaults[key]?.hash != hash {
                state.defaults[key] = .init(hash: hash, modified: now, synced: state.defaults[key]?.synced)
            }
        }

        let scan = CloudSyncHome.scan(root: root)
        for (rel, sig) in scan.signatures where state.home[rel]?.hash != sig.hash {
            state.home[rel] = .init(hash: sig.hash, modified: sig.modified, synced: state.home[rel]?.synced)
        }
        for (rel, entry) in state.home
            where scan.signatures[rel] == nil && !scan.skipped.contains(rel) && entry.hash != CloudSyncState.deletedHash
        {
            if entry.synced == nil {
                state.home[rel] = nil
            } else {
                state.home[rel] = .init(hash: CloudSyncState.deletedHash, modified: now, synced: entry.synced)
            }
        }
        return scan
    }

    // MARK: Fetch

    private func fetch(_ state: inout CloudSyncState, root: URL) async throws -> Bool {
        var token = state.changeToken.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        var applied = false
        owner.applyingRemote = true
        defer { owner.applyingRemote = false }
        var more = true
        while more {
            let changes = try await database.recordZoneChanges(inZoneWith: Self.zoneID, since: token)
            for (_, result) in changes.modificationResultsByID {
                if case .success(let modification) = result,
                   apply(modification.record, &state, root: root)
                {
                    applied = true
                }
            }
            for deletion in changes.deletions where applyDeletion(deletion.recordID, &state, root: root) {
                applied = true
            }
            token = changes.changeToken
            more = changes.moreComing
        }
        state.changeToken = token.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        return applied
    }

    private func apply(_ record: CKRecord, _ state: inout CloudSyncState, root: URL) -> Bool {
        let remoteModified = record["modified"] as? Date ?? record.modificationDate ?? .distantPast
        switch record.recordType {
        case Self.defaultType:
            guard let key = record["key"] as? String, CloudSyncPolicy.isSyncedDefaultsKey(key),
                  let payload = record["value"] as? Data
            else { return false }
            let remoteHash = CloudSyncState.digest(payload)
            let local = state.defaults[key]
            if let local, local.hash == remoteHash {
                state.defaults[key]?.synced = remoteHash
                return false
            }
            if let local, !CloudSyncPolicy.preferRemote(
                localModified: local.modified, remoteModified: remoteModified, localEverSynced: local.synced != nil
            ) {
                return false
            }
            guard CloudSyncDefaults.apply(payload, to: key, bootstrap: local?.synced == nil) else { return false }
            let newHash = CloudSyncDefaults.payload(for: key).map(CloudSyncState.digest) ?? remoteHash
            state.defaults[key] = .init(hash: newHash, modified: remoteModified, synced: remoteHash)
            return true

        case Self.homeType:
            guard let rel = record["path"] as? String, !CloudSyncPolicy.homePathExcluded(rel),
                  let asset = record["file"] as? CKAsset, let file = asset.fileURL
            else { return false }
            if let local = state.home[rel], !CloudSyncPolicy.preferRemote(
                localModified: local.modified, remoteModified: remoteModified, localEverSynced: local.synced != nil
            ) {
                return false
            }
            guard let sig = CloudSyncHome.write(asset: file, rel: rel, root: root, modified: remoteModified) else {
                return false
            }
            state.home[rel] = .init(hash: sig, modified: remoteModified, synced: sig)
            return true

        default:
            return false
        }
    }

    /// A HOME file deleted elsewhere goes away here only if this device has
    /// not edited it since the last sync.
    private func applyDeletion(_ id: CKRecord.ID, _ state: inout CloudSyncState, root: URL) -> Bool {
        guard id.recordName.hasPrefix("home."),
              let rel = state.home.keys.first(where: { CloudSyncState.homeRecordName($0) == id.recordName }),
              let entry = state.home[rel]
        else { return false }
        state.home[rel] = nil
        guard entry.hash == entry.synced, entry.hash != CloudSyncState.deletedHash else { return false }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(rel))
        return true
    }

    // MARK: Push

    private func push(_ state: inout CloudSyncState, root: URL) async throws -> Int {
        var saves: [(CKRecord, kind: Kind)] = []
        var deletes: [(CKRecord.ID, rel: String)] = []

        for (key, entry) in state.defaults where entry.needsPush {
            guard let payload = CloudSyncDefaults.payload(for: key) else { continue }
            let hash = CloudSyncState.digest(payload)
            let record = CKRecord(recordType: Self.defaultType, recordID: recordID(CloudSyncState.defaultsRecordName(key)))
            record["key"] = key as CKRecordValue
            record["value"] = payload as CKRecordValue
            record["modified"] = entry.modified as CKRecordValue
            saves.append((record, .defaults(key, hash)))
        }
        for (rel, entry) in state.home where entry.needsPush {
            let id = recordID(CloudSyncState.homeRecordName(rel))
            if entry.hash == CloudSyncState.deletedHash {
                deletes.append((id, rel))
                continue
            }
            let record = CKRecord(recordType: Self.homeType, recordID: id)
            record["path"] = rel as CKRecordValue
            record["file"] = CKAsset(fileURL: root.appendingPathComponent(rel))
            record["modified"] = entry.modified as CKRecordValue
            saves.append((record, .home(rel, entry.hash)))
        }

        var failures = 0
        var saveIndex = 0
        var deleteIndex = 0
        while saveIndex < saves.count || deleteIndex < deletes.count {
            let saveChunk = Array(saves[saveIndex..<min(saves.count, saveIndex + Self.batchSize)])
            let room = Self.batchSize - saveChunk.count
            let deleteChunk = Array(deletes[deleteIndex..<min(deletes.count, deleteIndex + room)])
            saveIndex += saveChunk.count
            deleteIndex += deleteChunk.count

            let result = try await database.modifyRecords(
                saving: saveChunk.map(\.0),
                deleting: deleteChunk.map(\.0),
                savePolicy: .allKeys,
                atomically: false
            )
            for (record, kind) in saveChunk {
                guard case .success = result.saveResults[record.recordID] else { failures += 1; continue }
                switch kind {
                case .defaults(let key, let hash): state.defaults[key]?.synced = hash
                case .home(let rel, let hash): state.home[rel]?.synced = hash
                }
            }
            for (id, rel) in deleteChunk {
                switch result.deleteResults[id] {
                case .success?:
                    state.home[rel] = nil
                case .failure(let error as CKError) where error.code == .unknownItem:
                    state.home[rel] = nil
                default:
                    failures += 1
                }
            }
        }
        return failures
    }

    private enum Kind {
        case defaults(String, String)
        case home(String, String)
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: Self.zoneID)
    }

    // MARK: Account

    private func accountProblem() async -> String? {
        do {
            switch try await container.accountStatus() {
            case .available: return nil
            case .noAccount: return "Sign in to iCloud in Settings to sync."
            case .restricted: return "iCloud is restricted on this device."
            case .temporarilyUnavailable: return "iCloud is temporarily unavailable."
            case .couldNotDetermine: return "Could not reach iCloud."
            @unknown default: return "iCloud account unavailable."
            }
        } catch {
            return "Could not reach iCloud."
        }
    }

    private static func describe(_ error: Error) -> Outcome {
        guard let ck = error as? CKError else { return .failed(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated: return .unavailable("Sign in to iCloud in Settings to sync.")
        case .networkUnavailable, .networkFailure: return .failed("offline")
        case .quotaExceeded: return .failed("iCloud storage is full")
        case .permissionFailure, .badContainer, .missingEntitlement:
            return .unavailable("This build is not signed for iCloud.")
        default: return .failed(ck.localizedDescription)
        }
    }
}
