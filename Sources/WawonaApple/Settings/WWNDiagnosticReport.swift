import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#endif
#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
import UIKit
#endif

@_silgen_name("wwn_log_ring_dump")
private func wwn_log_ring_dump(_ machineId: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("WWNStringFree")
private func WWNStringFree(_ s: UnsafeMutablePointer<CChar>?)

/// About → Copy Logs (Swift port of legacy `wwnCopyDiagnosticReportMachineOnly:`).
enum WWNDiagnosticReport {
    static func copyRecentLogs(machineOnly: Bool = false) {
        let text = build(machineOnly: machineOnly)
        #if os(tvOS)
        _ = text
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #elseif os(iOS) || os(visionOS)
        if UIApplication.shared.applicationState == .active {
            UIPasteboard.general.string = text
        }
        #endif
    }

    static func build(machineOnly: Bool) -> String {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        var out = "### Wawona diagnostics\n"
        out += "Wawona: \(version)\n"
        if !build.isEmpty {
            out += "Build: \(build)\n"
        }
        out += "Host: \(hostSummary())\n"
        out += "Bundle: \(Bundle.main.bundleIdentifier ?? "")\n"
        out += "\n### Active machine\n"
        if let mid = WWNMachineProfileStore.activeMachineId(), !mid.isEmpty {
            out += "id: \(mid)\n"
            if let profile = WWNMachineProfileStore.profile(byId: mid) {
                out += "name: \(profile.name)\n"
                out += "type: \(profile.type)\n"
            }
        } else {
            out += "(none)\n"
        }
        out += "\n### Logs\n```\n"
        if machineOnly {
            guard let mid = WWNMachineProfileStore.activeMachineId(), !mid.isEmpty else {
                out += "(no active machine selected)\n```\n"
                return out
            }
            out += logRingDump(machineId: mid)
        } else {
            out += logRingDump(machineId: nil)
        }
        out += "\n```\n"
        out +=
            "\nGitHub bug form: https://github.com/Wawona/Wawona/issues/new?template=bug.yml\n"
        return out
    }

    private static func logRingDump(machineId: String?) -> String {
        let dump: UnsafeMutablePointer<CChar>?
        if let machineId {
            dump = machineId.withCString { wwn_log_ring_dump($0) }
        } else {
            dump = wwn_log_ring_dump(nil)
        }
        guard let dump else { return "(log ring unavailable)" }
        defer { WWNStringFree(dump) }
        return String(cString: dump)
    }

    private static func hostSummary() -> String {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #elseif os(iOS)
        let v = UIDevice.current.systemVersion
        let idiom = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        return "\(idiom) \(v)"
        #elseif os(tvOS)
        return "tvOS \(UIDevice.current.systemVersion)"
        #elseif os(visionOS)
        return "visionOS \(UIDevice.current.systemVersion)"
        #else
        return "Apple"
        #endif
    }
}
