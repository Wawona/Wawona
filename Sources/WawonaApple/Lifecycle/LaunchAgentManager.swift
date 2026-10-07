#if os(macOS)
import AppKit
import Foundation

@objc(WWNLaunchAgentManager)
public final class WWNLaunchAgentManager: NSObject {

    private static let compositorLabel = "com.aspauldingcode.wawona.compositorhost"
    private static let menuBarLabel = "com.aspauldingcode.wawona.menubar"
    private static let appLaunchLabel = "com.aspauldingcode.wawona.applaunch"

    @objc public static let sharedManager: WWNLaunchAgentManager = {
        WWNLaunchAgentManager()
    }()

    @objc public func launchAgentsDirectory() -> String {
        NSHomeDirectory().appending("/Library/LaunchAgents")
    }

    @objc(plistPathForLabel:)
    public func plistPath(forLabel label: String) -> String {
        launchAgentsDirectory().appending("/\(label).plist")
    }

    @objc public func mainExecutablePath() -> String {
        let path = Bundle.main.executablePath
        return path?.isEmpty == false ? path! : "/Applications/Wawona.app/Contents/MacOS/Wawona"
    }

    @objc public func openToolPath() -> String {
        FileManager.default.fileExists(atPath: "/usr/bin/open") ? "/usr/bin/open" : "/bin/open"
    }

    @objc public func baseEnvironment() -> [String: String] {
        let uid = getuid()
        return [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "XDG_RUNTIME_DIR": "/tmp/wawona-\(uid)",
            "WAYLAND_DISPLAY": "wayland-0",
        ]
    }

    @objc public func compositorAgentPlist() -> [String: Any] {
        let execPath = mainExecutablePath()
        let uid = getuid()
        return [
            "Label": Self.compositorLabel,
            "ProgramArguments": [execPath, "--compositor-host"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 5,
            "StandardOutPath": "/tmp/wawona-compositor-\(uid).log",
            "StandardErrorPath": "/tmp/wawona-compositor-\(uid).error.log",
            "EnvironmentVariables": baseEnvironment(),
        ]
    }

    @objc public func menuBarAgentPlist() -> [String: Any] {
        let execPath = mainExecutablePath()
        let uid = getuid()
        return [
            "Label": Self.menuBarLabel,
            "ProgramArguments": [execPath, "--menubar"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 5,
            "StandardOutPath": "/tmp/wawona-menubar-\(uid).log",
            "StandardErrorPath": "/tmp/wawona-menubar-\(uid).error.log",
            "EnvironmentVariables": baseEnvironment(),
        ]
    }

    @objc public func appLaunchAgentPlist() -> [String: Any] {
        var bundlePath = Bundle.main.bundlePath
        if bundlePath.isEmpty {
            bundlePath = "/Applications/Wawona.app"
        }
        let uid = getuid()
        return [
            "Label": Self.appLaunchLabel,
            "ProgramArguments": [openToolPath(), bundlePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": "/tmp/wawona-applaunch-\(uid).log",
            "StandardErrorPath": "/tmp/wawona-applaunch-\(uid).error.log",
            "EnvironmentVariables": baseEnvironment(),
        ]
    }

    @objc(writePlist:toPath:error:)
    public func writePlist(_ plist: [String: Any], toPath path: String, error: NSErrorPointer) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch let err as NSError {
                error?.pointee = err
                return false
            }
        }
        guard (plist as NSDictionary).write(toFile: path, atomically: true) else {
            error?.pointee = NSError(
                domain: "com.aspauldingcode.Wawona.LaunchAgent",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write launch agent plist."]
            )
            return false
        }
        return true
    }

    @objc public func launchctlDomain() -> String {
        "gui/\(getuid())"
    }

    @objc(runLaunchctlWithArguments:)
    public func runLaunchctl(arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    @objc(bootstrapPlistAtPath:)
    public func bootstrapPlist(atPath path: String) -> Bool {
        let domain = launchctlDomain()
        _ = runLaunchctl(arguments: ["bootout", domain, path])
        return runLaunchctl(arguments: ["bootstrap", domain, path])
    }

    @objc(kickstartLabel:)
    public func kickstartLabel(_ label: String) -> Bool {
        runLaunchctl(arguments: ["kickstart", "-k", "\(launchctlDomain())/\(label)"])
    }

    @objc(bootoutLabel:)
    public func bootoutLabel(_ label: String) -> Bool {
        runLaunchctl(arguments: ["bootout", "\(launchctlDomain())/\(label)"])
    }

    @objc(isLabelLoaded:)
    public func isLabelLoaded(_ label: String) -> Bool {
        runLaunchctl(arguments: ["print", "\(launchctlDomain())/\(label)"])
    }

    @objc(installCompositorAndMenuAgents:)
    public func installCompositorAndMenuAgents(_ error: NSErrorPointer) -> Bool {
        let compositorPath = plistPath(forLabel: Self.compositorLabel)
        let menuPath = plistPath(forLabel: Self.menuBarLabel)
        guard writePlist(compositorAgentPlist(), toPath: compositorPath, error: error),
              writePlist(menuBarAgentPlist(), toPath: menuPath, error: error) else {
            return false
        }
        let compositorOK = bootstrapPlist(atPath: compositorPath)
        let menuOK = bootstrapPlist(atPath: menuPath)
        let compositorKick = kickstartLabel(Self.compositorLabel)
        let menuKick = kickstartLabel(Self.menuBarLabel)
        return compositorOK && menuOK && compositorKick && menuKick
    }

    @objc(ensureCompositorAndMenuAgents:)
    public func ensureCompositorAndMenuAgents(_ error: NSErrorPointer) -> Bool {
        _ = error
        let compositorPath = plistPath(forLabel: Self.compositorLabel)
        let menuPath = plistPath(forLabel: Self.menuBarLabel)
        let fm = FileManager.default
        if !fm.fileExists(atPath: compositorPath) || !fm.fileExists(atPath: menuPath) {
            return installCompositorAndMenuAgents(error)
        }
        if !isLabelLoaded(Self.compositorLabel), bootstrapPlist(atPath: compositorPath) {
            _ = kickstartLabel(Self.compositorLabel)
        }
        if !isLabelLoaded(Self.menuBarLabel), bootstrapPlist(atPath: menuPath) {
            _ = kickstartLabel(Self.menuBarLabel)
        }
        return true
    }

    @objc(ensureCompositorAgent:)
    public func ensureCompositorAgent(_ error: NSErrorPointer) -> Bool {
        let compositorPath = plistPath(forLabel: Self.compositorLabel)
        if !FileManager.default.fileExists(atPath: compositorPath) {
            guard writePlist(compositorAgentPlist(), toPath: compositorPath, error: error) else {
                return false
            }
        }
        if !isLabelLoaded(Self.compositorLabel) {
            guard bootstrapPlist(atPath: compositorPath) else { return false }
            _ = kickstartLabel(Self.compositorLabel)
        }
        var menuError: NSError?
        guard ensureMenuBarAgent(&menuError) else {
            error?.pointee = menuError
            return false
        }
        return true
    }

    @objc(ensureMenuBarAgent:)
    public func ensureMenuBarAgent(_ error: NSErrorPointer) -> Bool {
        _ = error
        let menuPath = plistPath(forLabel: Self.menuBarLabel)
        if !FileManager.default.fileExists(atPath: menuPath) {
            guard writePlist(menuBarAgentPlist(), toPath: menuPath, error: error) else {
                return false
            }
        }
        if !isLabelLoaded(Self.menuBarLabel) {
            guard bootstrapPlist(atPath: menuPath) else { return false }
            _ = kickstartLabel(Self.menuBarLabel)
        }
        return true
    }

    @objc(removePlistAtPath:)
    public func removePlist(atPath path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return true }
        return (try? FileManager.default.removeItem(atPath: path)) != nil
    }

    @objc public func restartCompositorAgent() -> Bool {
        kickstartLabel(Self.compositorLabel)
    }

    @objc public func stopCompositorAgent() -> Bool {
        let path = plistPath(forLabel: Self.compositorLabel)
        let stopped = bootoutLabel(Self.compositorLabel)
        let removed = removePlist(atPath: path)
        return stopped || removed
    }

    @objc public func startCompositorAgent() -> Bool {
        let compositorPath = plistPath(forLabel: Self.compositorLabel)
        if !FileManager.default.fileExists(atPath: compositorPath) {
            var err: NSError?
            guard writePlist(compositorAgentPlist(), toPath: compositorPath, error: &err) else {
                return false
            }
        }
        let ok = bootstrapPlist(atPath: compositorPath)
        let kicked = kickstartLabel(Self.compositorLabel)
        var menuErr: NSError?
        let menuReady = ensureMenuBarAgent(&menuErr)
        return ok && kicked && menuReady
    }

    @objc public func stopMenuBarAgent() -> Bool {
        let path = plistPath(forLabel: Self.menuBarLabel)
        let stopped = bootoutLabel(Self.menuBarLabel)
        let removed = removePlist(atPath: path)
        return stopped || removed
    }

    @objc public func stopCompositorAndMenuAgents() -> Bool {
        let menu = stopMenuBarAgent()
        let compositor = stopCompositorAgent()
        return menu && compositor
    }

    @objc public func isCompositorAgentLoaded() -> Bool { isLabelLoaded(Self.compositorLabel) }
    @objc public func isMenuBarAgentLoaded() -> Bool { isLabelLoaded(Self.menuBarLabel) }
    @objc public func isAppLaunchAgentLoaded() -> Bool { isLabelLoaded(Self.appLaunchLabel) }

    @objc public func enableAppLaunchAtLogin() -> Bool {
        let path = plistPath(forLabel: Self.appLaunchLabel)
        var err: NSError?
        guard writePlist(appLaunchAgentPlist(), toPath: path, error: &err) else { return false }
        return bootstrapPlist(atPath: path) && kickstartLabel(Self.appLaunchLabel)
    }

    @objc public func disableAppLaunchAtLogin() -> Bool {
        let path = plistPath(forLabel: Self.appLaunchLabel)
        let stopped = bootoutLabel(Self.appLaunchLabel)
        try? FileManager.default.removeItem(atPath: path)
        return stopped
    }
}
#endif
