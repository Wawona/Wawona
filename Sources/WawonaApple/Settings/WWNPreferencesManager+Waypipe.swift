import Foundation
#if canImport(Darwin)
import Darwin
#endif

extension WWNPreferencesManager {
    private func stringPref(_ key: String, default defaultValue: String) -> String {
        defs.string(forKey: key) ?? defaultValue
    }

    private func stringOrNumberPref(_ key: String, default defaultValue: String) -> String {
        if let s = defs.string(forKey: key) { return s }
        if let n = defs.object(forKey: key) as? NSNumber { return n.stringValue }
        return defaultValue
    }

    @objc public func waypipeDisplay() -> String {
        #if os(iOS) || targetEnvironment(simulator)
        var value = defs.string(forKey: kWWNPrefsWaypipeDisplay) ?? ""
        if value == "w0" || value == "w-0" {
            value = "wayland-0"
            defs.set(value, forKey: kWWNPrefsWaypipeDisplay)
        }
        return value.isEmpty ? "wayland-0" : value
        #else
        return "wayland-\(waylandDisplayNumber())"
        #endif
    }

    @objc public func setWaypipeDisplay(_ display: String?) {
        #if os(iOS) || targetEnvironment(simulator)
        var value = display ?? ""
        if value == "w0" || value == "w-0" { value = "wayland-0" }
        if value.isEmpty {
            defs.removeObject(forKey: kWWNPrefsWaypipeDisplay)
        } else {
            defs.set(value, forKey: kWWNPrefsWaypipeDisplay)
        }
        #else
        guard let display, !display.isEmpty else { return }
        var number = 0
        if display.hasPrefix("wayland-") {
            number = Int(display.dropFirst(8)) ?? 0
        } else {
            number = Int(display) ?? 0
        }
        setWaylandDisplayNumber(number)
        #endif
    }

    @objc public func waypipeSocket() -> String {
        #if os(iOS) || targetEnvironment(simulator)
        let runtimeDir = Self.preferredSharedRuntimeDir()
        if !runtimeDir.isEmpty {
            let display = waypipeDisplay()
            let preferred = (runtimeDir as NSString).appendingPathComponent(display.isEmpty ? "wayland-0" : display)
            let stored = defs.string(forKey: kWWNPrefsWaypipeSocket) ?? ""
            if stored != preferred {
                defs.set(preferred, forKey: kWWNPrefsWaypipeSocket)
            }
            return preferred
        }
        #endif
        if let value = defs.string(forKey: kWWNPrefsWaypipeSocket) { return value }
        #if os(iOS) || targetEnvironment(simulator)
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("waypipe")
        #else
        return "/tmp/wawona-waypipe-\(getuid()).sock"
        #endif
    }

    @objc public func setWaypipeSocket(_ socket: String) {
        defs.set(socket, forKey: kWWNPrefsWaypipeSocket)
    }

    @objc public func waypipeCompress() -> String { stringPref(kWWNPrefsWaypipeCompress, default: "lz4") }
    @objc public func setWaypipeCompress(_ compress: String) { defs.set(compress, forKey: kWWNPrefsWaypipeCompress) }

    @objc public func waypipeCompressLevel() -> String { stringOrNumberPref(kWWNPrefsWaypipeCompressLevel, default: "7") }
    @objc public func setWaypipeCompressLevel(_ level: String) { defs.set(level, forKey: kWWNPrefsWaypipeCompressLevel) }

    @objc public func waypipeThreads() -> String { stringOrNumberPref(kWWNPrefsWaypipeThreads, default: "0") }
    @objc public func setWaypipeThreads(_ threads: String) { defs.set(threads, forKey: kWWNPrefsWaypipeThreads) }

    @objc public func waypipeVideo() -> String { stringPref(kWWNPrefsWaypipeVideo, default: "none") }
    @objc public func setWaypipeVideo(_ video: String) { defs.set(video, forKey: kWWNPrefsWaypipeVideo) }

    @objc public func waypipeVideoEncoding() -> String { stringPref(kWWNPrefsWaypipeVideoEncoding, default: "hw") }
    @objc public func setWaypipeVideoEncoding(_ encoding: String) { defs.set(encoding, forKey: kWWNPrefsWaypipeVideoEncoding) }

    @objc public func waypipeVideoDecoding() -> String { stringPref(kWWNPrefsWaypipeVideoDecoding, default: "hw") }
    @objc public func setWaypipeVideoDecoding(_ decoding: String) { defs.set(decoding, forKey: kWWNPrefsWaypipeVideoDecoding) }

    @objc public func waypipeVideoBpf() -> String {
        if let s = defs.string(forKey: kWWNPrefsWaypipeVideoBpf) { return s }
        if let n = defs.object(forKey: kWWNPrefsWaypipeVideoBpf) as? NSNumber, n.doubleValue > 0 {
            return n.stringValue
        }
        return ""
    }

    @objc public func setWaypipeVideoBpf(_ bpf: String) { defs.set(bpf, forKey: kWWNPrefsWaypipeVideoBpf) }

    @objc public func waypipeSSHEnabled() -> Bool { true }

    @objc public func setWaypipeSSHEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsWaypipeSSHEnabled)
    }

    @objc public func waypipeSSHHost() -> String { stringPref(kWWNPrefsWaypipeSSHHost, default: "") }
    @objc public func setWaypipeSSHHost(_ host: String) { defs.set(host, forKey: kWWNPrefsWaypipeSSHHost) }

    @objc public func waypipeSSHUser() -> String { stringPref(kWWNPrefsWaypipeSSHUser, default: "") }
    @objc public func setWaypipeSSHUser(_ user: String) { defs.set(user, forKey: kWWNPrefsWaypipeSSHUser) }

    @objc public func waypipeSSHBinary() -> String { stringPref(kWWNPrefsWaypipeSSHBinary, default: "ssh") }
    @objc public func setWaypipeSSHBinary(_ binary: String) { defs.set(binary, forKey: kWWNPrefsWaypipeSSHBinary) }

    @objc public func waypipeSSHAuthMethod() -> Int { defs.integer(forKey: kWWNPrefsWaypipeSSHAuthMethod) }
    @objc public func setWaypipeSSHAuthMethod(_ method: Int) { defs.set(method, forKey: kWWNPrefsWaypipeSSHAuthMethod) }

    @objc public func waypipeSSHKeyPath() -> String { stringPref(kWWNPrefsWaypipeSSHKeyPath, default: "") }
    @objc public func setWaypipeSSHKeyPath(_ keyPath: String) { defs.set(keyPath, forKey: kWWNPrefsWaypipeSSHKeyPath) }

    @objc public func waypipeSSHKeyPassphrase() -> String { stringPref(kWWNPrefsWaypipeSSHKeyPassphrase, default: "") }
    @objc public func setWaypipeSSHKeyPassphrase(_ passphrase: String?) {
        if let passphrase, !passphrase.isEmpty {
            defs.set(passphrase, forKey: kWWNPrefsWaypipeSSHKeyPassphrase)
        } else {
            defs.removeObject(forKey: kWWNPrefsWaypipeSSHKeyPassphrase)
        }
    }

    @objc public func waypipeSSHPassword() -> String { stringPref(kWWNPrefsWaypipeSSHPassword, default: "") }
    @objc public func setWaypipeSSHPassword(_ password: String?) {
        if let password, !password.isEmpty {
            defs.set(password, forKey: kWWNPrefsWaypipeSSHPassword)
        } else {
            defs.removeObject(forKey: kWWNPrefsWaypipeSSHPassword)
        }
    }

    @objc public func waypipeRemoteCommand() -> String { stringPref(kWWNPrefsWaypipeRemoteCommand, default: "") }
    @objc public func setWaypipeRemoteCommand(_ command: String) { defs.set(command, forKey: kWWNPrefsWaypipeRemoteCommand) }

    @objc public func waypipeCustomScript() -> String { stringPref(kWWNPrefsWaypipeCustomScript, default: "") }
    @objc public func setWaypipeCustomScript(_ script: String) { defs.set(script, forKey: kWWNPrefsWaypipeCustomScript) }

    @objc public func waypipeDebug() -> Bool { defs.bool(forKey: kWWNPrefsWaypipeDebug) }
    @objc public func setWaypipeDebug(_ enabled: Bool) { defs.set(enabled, forKey: kWWNPrefsWaypipeDebug) }

    @objc public func waypipeNoGpu() -> Bool { defs.bool(forKey: kWWNPrefsWaypipeNoGpu) }
    @objc public func setWaypipeNoGpu(_ enabled: Bool) { defs.set(enabled, forKey: kWWNPrefsWaypipeNoGpu) }

    @objc public func waypipeOneshot() -> Bool {
        #if os(iOS)
        return true
        #else
        return defs.bool(forKey: kWWNPrefsWaypipeOneshot)
        #endif
    }

    @objc public func setWaypipeOneshot(_ enabled: Bool) {
        #if !os(iOS)
        defs.set(enabled, forKey: kWWNPrefsWaypipeOneshot)
        #endif
    }

    @objc public func waypipeUnlinkSocket() -> Bool { defs.bool(forKey: kWWNPrefsWaypipeUnlinkSocket) }
    @objc public func setWaypipeUnlinkSocket(_ enabled: Bool) { defs.set(enabled, forKey: kWWNPrefsWaypipeUnlinkSocket) }

    @objc public func waypipeLoginShell() -> Bool { defs.bool(forKey: kWWNPrefsWaypipeLoginShell) }
    @objc public func setWaypipeLoginShell(_ enabled: Bool) { defs.set(enabled, forKey: kWWNPrefsWaypipeLoginShell) }

    @objc public func waypipeVsock() -> Bool { defs.bool(forKey: kWWNPrefsWaypipeVsock) }
    @objc public func setWaypipeVsock(_ enabled: Bool) { defs.set(enabled, forKey: kWWNPrefsWaypipeVsock) }

    @objc public func waypipeXwls() -> Bool { defs.bool(forKey: kWWNPrefsWaypipeXwls) }
    @objc public func setWaypipeXwls(_ enabled: Bool) { defs.set(enabled, forKey: kWWNPrefsWaypipeXwls) }

    @objc public func waypipeTitlePrefix() -> String { stringPref(kWWNPrefsWaypipeTitlePrefix, default: "") }
    @objc public func setWaypipeTitlePrefix(_ prefix: String) { defs.set(prefix, forKey: kWWNPrefsWaypipeTitlePrefix) }

    @objc public func waypipeSecCtx() -> String { stringPref(kWWNPrefsWaypipeSecCtx, default: "") }
    @objc public func setWaypipeSecCtx(_ secCtx: String) { defs.set(secCtx, forKey: kWWNPrefsWaypipeSecCtx) }

    @objc public func waypipeUseSSHConfig() -> Bool {
        if defs.object(forKey: kWWNPrefsWaypipeUseSSHConfig) == nil { return true }
        return defs.bool(forKey: kWWNPrefsWaypipeUseSSHConfig)
    }

    @objc public func setWaypipeUseSSHConfig(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsWaypipeUseSSHConfig)
    }
}
