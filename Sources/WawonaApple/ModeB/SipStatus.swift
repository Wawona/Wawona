import Foundation

/// SIP classify for Desktop Replacement. Replaces `WWNSipStatus.m`.
/// Parse `csrutil status` text only. Never invent CSR_* syscalls.
@objc(WWNSipStatusType)
public enum WWNSipStatusType: Int {
    case enabled = 0
    case disabled = 1
    case partiallyDisabled = 2
    case unknown = 3
}

@objc(WWNSipStatus)
public final class WWNSipStatus: NSObject {
    @objc public static func current() -> WWNSipStatusType {
        SipStatus.current().asObjC
    }

    @objc public static func describe(_ status: WWNSipStatusType) -> String {
        SipStatus(from: status).descriptionLabel
    }

    @objc public static func allowsDesktopReplacement(_ status: WWNSipStatusType) -> Bool {
        SipStatus(from: status).allowsDesktopReplacement
    }

    @objc public static func desktopReplacementHowToMessage() -> String {
        SipStatus.desktopReplacementHowToMessage
    }

    @objc(classifyStatusText:)
    public static func classifyStatusText(_ result: String) -> WWNSipStatusType {
        SipStatus.classify(statusText: result).asObjC
    }
}

/// Pure Swift API used by new SwiftUI / WawonaApple callers.
public enum SipStatus: Equatable, Sendable {
    case enabled
    case disabled
    case partiallyDisabled
    case unknown

    public static func current() -> SipStatus {
        #if os(macOS)
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        proc.arguments = ["status"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return .unknown
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return classify(statusText: text)
        #else
        return .unknown
        #endif
    }

    public static func classify(statusText: String) -> SipStatus {
        let trimmed = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        let head = firstLine.isEmpty ? trimmed : firstLine
        let custom =
            head.range(of: "Custom Configuration", options: .caseInsensitive) != nil
            || head.range(of: "unknown", options: .caseInsensitive) != nil
        if !custom, head.range(of: "status: disabled", options: .caseInsensitive) != nil {
            return .disabled
        }
        if custom || trimmed.contains("Debugging Restrictions: disabled") {
            return .partiallyDisabled
        }
        if head.range(of: "status: enabled", options: .caseInsensitive) != nil {
            return .enabled
        }
        return .unknown
    }

    public var descriptionLabel: String {
        switch self {
        case .enabled: return "Enabled"
        case .disabled: return "Fully Disabled"
        case .partiallyDisabled:
            return "Partially Disabled (Mode B needs Fully Disabled)"
        case .unknown: return "Unknown"
        }
    }

    public var allowsDesktopReplacement: Bool {
        self == .disabled
    }

    public static let desktopReplacementHowToMessage = """
        wwn-iland macOS Desktop Replacement (Mode B) replaces \
        SkyLight/WindowServer by injecting libwayland-mac.dylib into a root \
        compositor. That requires System Integrity Protection (SIP) fully \
        disabled. Not a normal App Store configuration.

        Why SIP must be fully off:
        Take Over disables kernel IOWatchdog, then unloads Apple's \
        watchdogd and WindowServer so framebufferd can own SkyLight. \
        DYLD_INSERT_LIBRARIES and Dobby also need SIP off. With SIP only \
        partially disabled (csrutil enable --without debug), launchctl \
        bootout of WindowServer returns 150. Debugging Restrictions off \
        is not enough.

        Unloading watchdogd without IOWatchdog disable panics immediately \
        on this macOS (2026-08-19).

        Required setup:
        1. Restart into Recovery (hold Power at boot, or Recovery partition).
        2. Open Terminal from Utilities.
        3. Run: csrutil disable
        4. Reboot normally.
        5. Verify: csrutil status should report \
        "System Integrity Protection status: disabled." \
        Wawona Settings → Desktop must show Fully Disabled.

        Do not use csrutil enable --without debug for Desktop Replacement.

        Android note: Wawona Desktop Replacement on Android does not change \
        SIP or system security. It uses the Android Launcher (HOME app) role \
        instead. No Recovery-mode steps are required on Android.
        """

    var asObjC: WWNSipStatusType {
        switch self {
        case .enabled: return .enabled
        case .disabled: return .disabled
        case .partiallyDisabled: return .partiallyDisabled
        case .unknown: return .unknown
        }
    }

    init(from status: WWNSipStatusType) {
        switch status {
        case .enabled: self = .enabled
        case .disabled: self = .disabled
        case .partiallyDisabled: self = .partiallyDisabled
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}
