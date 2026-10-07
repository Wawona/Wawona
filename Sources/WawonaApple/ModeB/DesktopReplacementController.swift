import Foundation
#if canImport(AppKit)
import AppKit
#endif

@objc public enum WWNModeBVerdict: Int {
    case ready = 0
    case blockedSip = 1
    case blockedCoverage = 2
    case blockedMissingHelper = 3
    case unavailable = 4
}

@objc(WWNModeBReadyReport)
public final class WWNModeBReadyReport: NSObject {
    @objc public var verdict: WWNModeBVerdict = .unavailable
    @objc public var token: String = ""
    @objc public var reason: String = ""
    @objc public var nextStep: String = ""
    @objc public var userSummary: String = ""
    @objc public var needsSipHowTo = false
    @objc public var canPrepareRequirements = false
}

@objc(WWNModeBCoverageReport)
public final class WWNModeBCoverageReport: NSObject {
    @objc public var statusLabel: String = ""
    @objc public var userSummary: String = ""
    @objc public var detailText: String = ""
    @objc public var pathBLabel: String = ""
    @objc public var safetyLabel: String = ""
    @objc public var coverageOk = false
    @objc public var needsHeal = false
    @objc public var needsReboot = false
    @objc public var rebootForAppleJob = false
    @objc public var canPrepare = false
    @objc public var pathBInstalled = false
    @objc public var pathBLive = false
    @objc public var dualPath = false
    @objc public var watchdogdPid: String?
    @objc public var doctorText: String?
}

@objc(WWNModeBMenuBarStatus)
public final class WWNModeBMenuBarStatus: NSObject {
    @objc public var state: String = "Mode A"
    @objc public var tooltip: String = ""
    @objc public var canTakeOver = false
    @objc public var canRestore = false
    @objc public var canRestartMac = false
    @objc public var canPrepare = false
}

/// Mode B Desktop Replacement glue. Never unloads watchdogd or attaches lldb.
@objc(WWNDesktopReplacementController)
public final class WWNDesktopReplacementController: NSObject {
    @objc public static let sharedController = WWNDesktopReplacementController()

    @objc public func shouldEngageModeB() -> Bool {
        WWNSipStatus.allowsDesktopReplacement(WWNSipStatus.current())
            && UserDefaults.standard.bool(forKey: "DesktopReplacementEnabled")
    }

    @objc(isDesktopMachine:)
    public func isDesktopMachine(_ profile: WWNMachineProfile) -> Bool {
        let selected = UserDefaults.standard.string(forKey: kWWNPrefsDesktopReplacementMachineId) ?? ""
        if !selected.isEmpty, profile.machineId == selected {
            return true
        }
        return WWNMachineProfileStore.profileEligibleForDesktopReplacement(profile)
    }

    @objc public func ensureDesktopMachineSelected(_ error: NSErrorPointer) -> Bool {
        let selected = UserDefaults.standard.string(forKey: kWWNPrefsDesktopReplacementMachineId) ?? ""
        if !selected.isEmpty,
           let profile = WWNMachineProfileStore.profile(byId: selected),
           WWNMachineProfileStore.profileEligibleForDesktopReplacement(profile) {
            return true
        }
        error?.pointee = NSError(domain: "WWNModeB", code: 3, userInfo: [
            NSLocalizedDescriptionKey:
                "Choose a Native Shell Weston or Niri machine under Settings → Desktop."
        ])
        return false
    }

    @objc public func bundledDylibPath() -> String? {
        Bundle.main.path(forResource: "libwayland-mac", ofType: "dylib", inDirectory: "Library/Wawona/iland")
    }

    @objc public func iowatchdogStickyAckPresent() -> Bool {
        FileManager.default.fileExists(atPath: "/var/db/wwn-iowatchdog/claim-ok")
    }

    @objc public func iowatchdogStickyAckStatusSummary() -> String {
        iowatchdogStickyAckPresent() ? "claim-ok present" : "claim-ok missing"
    }

    @objc public func injectionPreflightError() -> NSError? {
        if !WWNSipStatus.allowsDesktopReplacement(WWNSipStatus.current()) {
            return NSError(domain: "WWNModeB", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "SIP must be fully disabled for Desktop Replacement."
            ])
        }
        return nil
    }

    @objc(engageForProfile:error:)
    public func engage(for profile: WWNMachineProfile, error: NSErrorPointer) -> Bool {
        if let err = injectionPreflightError() {
            error?.pointee = err
            return false
        }
        _ = profile
        // Helper scripts own Take Over. Swift never unloads watchdogd.
        return false
    }

    @objc public func engageSelectedDesktopMachine(_ error: NSErrorPointer) -> Bool {
        engage(for: WWNMachineProfile.defaultProfile(), error: error)
    }

    @objc public func disengage() -> Bool { true }
    @objc public func resumeAfterAquaLogin() {}
    @objc public func presentPendingSessionFailureAlert() {}
    @objc public func reconcilePrefsWithCurrentSip() -> Bool {
        if !WWNSipStatus.allowsDesktopReplacement(WWNSipStatus.current()) {
            UserDefaults.standard.set(false, forKey: "DesktopReplacementEnabled")
            return false
        }
        return true
    }

    @objc public func cliStatus() -> Int32 { 0 }
    @objc public func cliReady() -> Int32 { shouldEngageModeB() ? 0 : 1 }

    @objc public func evaluateClassicReadiness() -> WWNModeBReadyReport {
        let report = WWNModeBReadyReport()
        if !WWNSipStatus.allowsDesktopReplacement(WWNSipStatus.current()) {
            report.verdict = .blockedSip
            report.needsSipHowTo = true
            report.userSummary = "Turn SIP fully off before Desktop Replacement."
            return report
        }
        report.verdict = .blockedMissingHelper
        report.canPrepareRequirements = true
        report.userSummary = "Stage Desktop Replacement from Settings, then Replace now."
        return report
    }

    @objc public func isModeBCompositorLive() -> Bool { false }
    @objc public func isClassicTakeoverLive() -> Bool { false }

    @objc(menuBarDesktopStatusRefreshingGate:)
    public func menuBarDesktopStatus(refreshingGate refresh: Bool) -> WWNModeBMenuBarStatus {
        _ = refresh
        let s = WWNModeBMenuBarStatus()
        s.state = shouldEngageModeB() ? "Armed" : "Mode A"
        return s
    }

    @objc public func requestNativeMacOSRestart(_ error: NSErrorPointer) -> Bool {
        error?.pointee = NSError(domain: "WWNModeB", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Restart from the Apple menu after Path B staging."
        ])
        return false
    }

    @objc public func installDesktopReplacementRequirements(_ error: NSErrorPointer) -> Bool {
        _ = error
        return false
    }

    @objc public func syncDesktopHostInstallArtifactsIfNeeded(_ error: NSErrorPointer) -> Bool {
        _ = error
        return true
    }

    @objc(installedHelperMatchesCurrentBuildForProfile:)
    public func installedHelperMatchesCurrentBuild(for profile: WWNMachineProfile) -> Bool {
        _ = profile
        return false
    }

    @objc public func ensureWatchdogSafetyReady(_ error: NSErrorPointer) -> Bool {
        // Never unload watchdogd from Swift.
        true
    }

    @objc(presentRestartAfterPrepareWithMessage:)
    public func presentRestartAfterPrepare(withMessage message: String) { _ = message }
    @objc public func presentDesktopReplacementPrepareFlow() {}
    @objc public func presentReplaceNowFlow() {}
    @objc public func presentReadyTakeOverOffer() {}
    @objc public func endClassicSession() -> Bool { true }

    @objc public func evaluateWatchdogCoverage() -> WWNModeBCoverageReport {
        let r = WWNModeBCoverageReport()
        r.statusLabel = "Mode A"
        r.coverageOk = true
        r.safetyLabel = "watchdogd left running"
        return r
    }

    @objc public func runWatchdogDoctor(_ error: NSErrorPointer) -> WWNModeBCoverageReport? {
        _ = error
        return evaluateWatchdogCoverage()
    }

    @objc public func healWatchdogCoverage(_ error: NSErrorPointer) -> Bool {
        _ = error
        return false
    }

    @objc public func presentWatchdogCoverageCheck() {}
    @objc public func presentWatchdogHealFlow() {}
    @objc public func cliPrepare() -> Int32 { 1 }
    @objc(cliEngageKeepWindowServer:)
    public func cliEngage(keepWindowServer: Bool) -> Int32 {
        _ = keepWindowServer
        return 1
    }
    @objc public func cliDisengage() -> Int32 { 0 }
    @objc public func cliStage() -> Int32 { 1 }
    @objc(cliSelectDesktopMachine:)
    public func cliSelectDesktopMachine(_ idOrName: String) -> Int32 {
        _ = idOrName
        return 0
    }
}
