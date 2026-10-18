import Foundation

/// CloudKit sync policy from `src/domain` (`cloud_sync`). Without the rust
/// archive (SPM tests) nothing syncs: there is no Swift copy of the key list.
public enum CloudSyncPolicy {
    public static let profilesKey = MachineProfileDomain.profilesKey

    public static var rustLinked: Bool {
        WawonaDomainBridge.symbol("wawona_cloud_sync_is_synced_key") != nil
    }

    public static func isSyncedDefaultsKey(_ key: String) -> Bool {
        typealias Fn = @convention(c) (UnsafePointer<CChar>?) -> Int32
        guard let sym = WawonaDomainBridge.symbol("wawona_cloud_sync_is_synced_key") else {
            return false
        }
        return key.withCString { unsafeBitCast(sym, to: Fn.self)($0) } != 0
    }

    public static func homePathExcluded(_ rel: String) -> Bool {
        typealias Fn = @convention(c) (UnsafePointer<CChar>?) -> Int32
        guard let sym = WawonaDomainBridge.symbol("wawona_cloud_sync_home_path_excluded") else {
            return true
        }
        return rel.withCString { unsafeBitCast(sym, to: Fn.self)($0) } != 0
    }

    public static var homeMaxFileBytes: UInt64 {
        typealias Fn = @convention(c) () -> UInt64
        guard let sym = WawonaDomainBridge.symbol("wawona_cloud_sync_home_max_file_bytes") else {
            return 0
        }
        return unsafeBitCast(sym, to: Fn.self)()
    }

    public static var homeMaxFiles: Int {
        typealias Fn = @convention(c) () -> UInt32
        guard let sym = WawonaDomainBridge.symbol("wawona_cloud_sync_home_max_files") else {
            return 0
        }
        return Int(unsafeBitCast(sym, to: Fn.self)())
    }

    public static func preferRemote(localModified: Date, remoteModified: Date, localEverSynced: Bool) -> Bool {
        typealias Fn = @convention(c) (Int64, Int64, Int32) -> Int32
        guard let sym = WawonaDomainBridge.symbol("wawona_cloud_sync_prefer_remote") else {
            return false
        }
        let local = Int64(localModified.timeIntervalSince1970 * 1000)
        let remote = Int64(remoteModified.timeIntervalSince1970 * 1000)
        return unsafeBitCast(sym, to: Fn.self)(local, remote, localEverSynced ? 1 : 0) != 0
    }

    public static func redactProfiles(_ json: String) -> String? {
        WawonaDomainBridge.callString1("wawona_cloud_sync_redact_profiles", json)
    }

    public static func mergeProfiles(local: String, remote: String, bootstrap: Bool) -> String? {
        typealias Fn = @convention(c) (
            UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32
        ) -> UnsafeMutablePointer<CChar>?
        typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        guard let sym = WawonaDomainBridge.symbol("wawona_cloud_sync_merge_profiles"),
              let freeSym = WawonaDomainBridge.symbol("wawona_domain_string_free")
        else {
            return nil
        }
        return local.withCString { cLocal in
            remote.withCString { cRemote in
                guard let raw = unsafeBitCast(sym, to: Fn.self)(cLocal, cRemote, bootstrap ? 1 : 0) else {
                    return nil
                }
                defer { unsafeBitCast(freeSym, to: FreeFn.self)(raw) }
                return String(cString: raw)
            }
        }
    }
}
