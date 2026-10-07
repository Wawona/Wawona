import Foundation
#if canImport(Security)
import Security
#endif

extension WWNPreferencesManager {
    // MARK: - Container defaults (standardUserDefaults quirk preserved)

    private var containerDefaults: UserDefaults { .standard }

    @objc public func containerDefaultImage() -> String {
        containerDefaults.string(forKey: kWWNPrefsContainerDefaultImage) ?? "alpine:3.20"
    }

    @objc public func setContainerDefaultImage(_ image: String) {
        containerDefaults.set(image, forKey: kWWNPrefsContainerDefaultImage)
    }

    @objc public func containerDefaultCommand() -> String {
        containerDefaults.string(forKey: kWWNPrefsContainerDefaultCommand) ?? "/bin/sh"
    }

    @objc public func setContainerDefaultCommand(_ command: String) {
        containerDefaults.set(command, forKey: kWWNPrefsContainerDefaultCommand)
    }

    @objc public func containerMemory() -> String {
        containerDefaults.string(forKey: kWWNPrefsContainerMemory) ?? ""
    }

    @objc public func setContainerMemory(_ memory: String) {
        containerDefaults.set(memory, forKey: kWWNPrefsContainerMemory)
    }

    @objc public func containerShmSize() -> String {
        containerDefaults.string(forKey: kWWNPrefsContainerShmSize) ?? ""
    }

    @objc public func setContainerShmSize(_ shmSize: String) {
        containerDefaults.set(shmSize, forKey: kWWNPrefsContainerShmSize)
    }

    @objc public func containerKernelPath() -> String {
        containerDefaults.string(forKey: kWWNPrefsContainerKernelPath) ?? ""
    }

    @objc public func setContainerKernelPath(_ path: String) {
        containerDefaults.set(path, forKey: kWWNPrefsContainerKernelPath)
    }

    @objc public func containerInitfsPath() -> String {
        containerDefaults.string(forKey: kWWNPrefsContainerInitfsPath) ?? ""
    }

    @objc public func setContainerInitfsPath(_ path: String) {
        containerDefaults.set(path, forKey: kWWNPrefsContainerInitfsPath)
    }

    @objc public func containerVsockPort() -> String {
        containerDefaults.string(forKey: kWWNPrefsContainerVsockPort) ?? "1024"
    }

    @objc public func setContainerVsockPort(_ port: String) {
        containerDefaults.set(port, forKey: kWWNPrefsContainerVsockPort)
    }

    // MARK: - SSH

    @objc public func sshHost() -> String { stringPref(kWWNPrefsSSHHost, default: "") }
    @objc public func setSshHost(_ host: String) { defs.set(host, forKey: kWWNPrefsSSHHost) }

    @objc public func sshUser() -> String { stringPref(kWWNPrefsSSHUser, default: "") }
    @objc public func setSshUser(_ user: String) { defs.set(user, forKey: kWWNPrefsSSHUser) }

    @objc public func sshPort() -> Int {
        let port = defs.integer(forKey: kWWNPrefsSSHPort)
        return port > 0 ? port : 22
    }

    @objc public func setSshPort(_ port: Int) {
        let clamped = (1...65535).contains(port) ? port : 22
        defs.set(clamped, forKey: kWWNPrefsSSHPort)
        defs.set("\(clamped)", forKey: "WaypipeSSHPort")
    }

    @objc public func sshAuthMethod() -> Int { defs.integer(forKey: kWWNPrefsSSHAuthMethod) }

    @objc public func setSshAuthMethod(_ method: Int) {
        defs.set(method, forKey: kWWNPrefsSSHAuthMethod)
        defs.set(method, forKey: kWWNPrefsWaypipeSSHAuthMethod)
    }

    @objc public func sshKeyPath() -> String { stringPref(kWWNPrefsSSHKeyPath, default: "") }

    @objc public func setSshKeyPath(_ keyPath: String) {
        defs.set(keyPath, forKey: kWWNPrefsSSHKeyPath)
        defs.set(keyPath, forKey: kWWNPrefsWaypipeSSHKeyPath)
    }

    @objc public func sshPassword() -> String { getSecureValue(forKey: kWWNPrefsSSHPassword) }

    @objc public func setSshPassword(_ password: String?) {
        setSecureValue(password, forKey: kWWNPrefsSSHPassword)
    }

    @objc public func sshKeyPassphrase() -> String { getSecureValue(forKey: kWWNPrefsSSHKeyPassphrase) }

    @objc public func setSshKeyPassphrase(_ passphrase: String?) {
        setSecureValue(passphrase, forKey: kWWNPrefsSSHKeyPassphrase)
        setWaypipeSSHKeyPassphrase(passphrase)
    }

    // MARK: - Secure storage (Keychain + defaults mirror)

    private func stringPref(_ key: String, default defaultValue: String) -> String {
        defs.string(forKey: key) ?? defaultValue
    }

    private func getSecureValue(forKey key: String) -> String {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.wawona.ssh",
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let val = String(data: data, encoding: .utf8), !val.isEmpty {
            return val
        }
        #endif
        return defs.string(forKey: key) ?? ""
    }

    private func setSecureValue(_ value: String?, forKey key: String) {
        #if canImport(Security)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.wawona.ssh",
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        if let value, !value.isEmpty, let data = value.data(using: .utf8) {
            var addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "io.wawona.ssh",
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrSynchronizable as String: true,
            ]
            if SecItemAdd(addQuery as CFDictionary, nil) != errSecSuccess {
                addQuery.removeValue(forKey: kSecAttrSynchronizable as String)
                SecItemAdd(addQuery as CFDictionary, nil)
            }
            defs.set(value, forKey: key)
        } else {
            defs.removeObject(forKey: key)
        }
        #else
        if let value, !value.isEmpty {
            defs.set(value, forKey: key)
        } else {
            defs.removeObject(forKey: key)
        }
        #endif
    }
}
