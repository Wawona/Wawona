import Foundation

extension WWNPreferencesManager {
    @objc public func syncFromCanonicalWawonaPreferences() {
        let defaults = defs
        let prefix = "wawona.pref."

        if let forceSSD = defaults.object(forKey: prefix + "forceSSD") as? Bool {
            setForceServerSideDecorations(forceSSD)
        } else if let forceSSD = defaults.object(forKey: prefix + "forceSSD") as? NSNumber {
            setForceServerSideDecorations(forceSSD.boolValue)
        }

        if let autoScale = defaults.object(forKey: prefix + "autoScale") as? Bool {
            setAutoScale(autoScale)
        } else if let autoScale = defaults.object(forKey: prefix + "autoScale") as? NSNumber {
            setAutoScale(autoScale.boolValue)
        }

        if let waylandDisplay = defaults.string(forKey: prefix + "waylandDisplay"), !waylandDisplay.isEmpty {
            setWaypipeDisplay(waylandDisplay)
        }
        if let sshHost = defaults.string(forKey: prefix + "sshHost"), !sshHost.isEmpty {
            setWaypipeSSHHost(sshHost)
        }
        if let sshUser = defaults.string(forKey: prefix + "sshUser"), !sshUser.isEmpty {
            setWaypipeSSHUser(sshUser)
        }
        if let sshPort = defaults.object(forKey: prefix + "sshPort") as? NSNumber {
            setSshPort(sshPort.intValue)
        }
        if let sshPassword = defaults.string(forKey: prefix + "sshPassword"), !sshPassword.isEmpty {
            setWaypipeSSHPassword(sshPassword)
        }

        if let inputProfile = defaults.string(forKey: prefix + "defaultInputProfile"), !inputProfile.isEmpty {
            let lower = inputProfile.lowercased()
            if ["touchpad", "pointer", "virtual", "trackpad"].contains(lower) {
                setTouchInputType("Touchpad")
            } else {
                setTouchInputType("Multi-Touch")
            }
        }

        if let renderer = defaults.string(forKey: prefix + "renderer"), !renderer.isEmpty {
            setVulkanDriver(renderer == "metal" ? "moltenvk" : renderer)
        }

        if defaults.object(forKey: prefix + "defaultWaypipeEnabled") != nil {
            setWaypipeSSHEnabled(defaults.bool(forKey: prefix + "defaultWaypipeEnabled"))
        }

        if let xwayland = defaults.object(forKey: prefix + "xwaylandSupport") {
            if let b = xwayland as? Bool {
                setWaypipeXwls(b)
            } else if let n = xwayland as? NSNumber {
                setWaypipeXwls(n.boolValue)
            }
        }
    }
}
