import Foundation
#if canImport(Security)
import Security
#endif

/// Synchronizes sensitive credentials (SSH passwords, passphrases, public keys)
/// with the Apple Keychain on supported Apple platforms.
///
/// Supports iCloud Keychain cross-device synchronization with graceful fallback
/// to local Keychain storage when iCloud Keychain is not provisioned.
@objc(WWNKeychain)
public final class WWNKeychain: NSObject, Sendable {
    @objc public static let shared = WWNKeychain()

    @objc public static let defaultService = "io.wawona.ssh"

    // MARK: - Key Identifiers

    public static let globalSSHPasswordKey = "global.sshPassword"
    public static let globalWaypipeSSHPasswordKey = "global.waypipeSSHPassword"
    public static let globalSSHKeyPassphraseKey = "global.sshKeyPassphrase"
    public static let globalSSHPublicKeyKey = "global.sshPublicKey"

    public static func machineSSHPasswordKey(_ machineID: String) -> String {
        "machine.\(machineID).sshPassword"
    }

    public static func machineSSHKeyPassphraseKey(_ machineID: String) -> String {
        "machine.\(machineID).sshKeyPassphrase"
    }

    public static func machineSSHPublicKeyKey(_ machineID: String) -> String {
        "machine.\(machineID).sshPublicKey"
    }

    // MARK: - Low-Level Keychain Operations

    @objc @discardableResult
    public func setString(
        _ value: String?,
        forKey key: String,
        service: String = WWNKeychain.defaultService
    ) -> Bool {
        #if canImport(Security)
        guard let value = value, !value.isEmpty else {
            return removeString(forKey: key, service: service)
        }
        guard let data = value.data(using: .utf8) else {
            return false
        }

        // Delete any existing item first to ensure clean state.
        removeString(forKey: key, service: service)

        // Attempt 1: Add with iCloud Keychain synchronization
        var syncAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: (kCFBooleanTrue as Any)
        ]

        var status = SecItemAdd(syncAttributes as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }

        // Attempt 2: Fallback to local Keychain without synchronizable attribute
        syncAttributes.removeValue(forKey: kSecAttrSynchronizable as String)
        status = SecItemAdd(syncAttributes as CFDictionary, nil)
        return status == errSecSuccess
        #else
        return false
        #endif
    }

    @objc
    public func string(
        forKey key: String,
        service: String = WWNKeychain.defaultService
    ) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: (kCFBooleanTrue as Any),
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
        #else
        return nil
        #endif
    }

    @objc @discardableResult
    public func removeString(
        forKey key: String,
        service: String = WWNKeychain.defaultService
    ) -> Bool {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }

    // MARK: - Typed SSH Helpers

    public func sshPassword(for machineID: String? = nil) -> String? {
        if let machineID = machineID, !machineID.isEmpty {
            return string(forKey: Self.machineSSHPasswordKey(machineID))
        }
        return string(forKey: Self.globalSSHPasswordKey)
    }

    @discardableResult
    public func setSSHPassword(_ value: String?, for machineID: String? = nil) -> Bool {
        if let machineID = machineID, !machineID.isEmpty {
            return setString(value, forKey: Self.machineSSHPasswordKey(machineID))
        }
        return setString(value, forKey: Self.globalSSHPasswordKey)
    }

    public func sshKeyPassphrase(for machineID: String? = nil) -> String? {
        if let machineID = machineID, !machineID.isEmpty {
            return string(forKey: Self.machineSSHKeyPassphraseKey(machineID))
        }
        return string(forKey: Self.globalSSHKeyPassphraseKey)
    }

    @discardableResult
    public func setSSHKeyPassphrase(_ value: String?, for machineID: String? = nil) -> Bool {
        if let machineID = machineID, !machineID.isEmpty {
            return setString(value, forKey: Self.machineSSHKeyPassphraseKey(machineID))
        }
        return setString(value, forKey: Self.globalSSHKeyPassphraseKey)
    }

    public func sshPublicKey(for machineID: String? = nil) -> String? {
        if let machineID = machineID, !machineID.isEmpty {
            return string(forKey: Self.machineSSHPublicKeyKey(machineID))
        }
        return string(forKey: Self.globalSSHPublicKeyKey)
    }

    @discardableResult
    public func setSSHPublicKey(_ value: String?, for machineID: String? = nil) -> Bool {
        if let machineID = machineID, !machineID.isEmpty {
            return setString(value, forKey: Self.machineSSHPublicKeyKey(machineID))
        }
        return setString(value, forKey: Self.globalSSHPublicKeyKey)
    }

    @discardableResult
    public func deleteSSHPassword(for machineID: String? = nil) -> Bool {
        setSSHPassword(nil, for: machineID)
    }

    @discardableResult
    public func deleteSSHKeyPassphrase(for machineID: String? = nil) -> Bool {
        setSSHKeyPassphrase(nil, for: machineID)
    }

    @discardableResult
    public func deleteSSHPublicKey(for machineID: String? = nil) -> Bool {
        setSSHPublicKey(nil, for: machineID)
    }
}

