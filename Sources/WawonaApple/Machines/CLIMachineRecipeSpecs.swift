#if os(macOS)
import Foundation

enum CLIMachineRecipeSpecs {
    static let desktopImageRef = "wawona-container-desktop:latest"

    static func stableMachineId(recipeKey: String) -> String {
        recipeKey.replacingOccurrences(of: ":", with: "-").lowercased()
    }

    static func swayConfig() -> String {
        """
        # Wawona nested sway (container / waypipe)
        output * bg #1a1b26 solid_color
        exec swaybg -c '#1a1b26'

        set $mod Mod1
        set $term foot

        bindsym $mod+Return exec $term
        bindsym $mod+Shift+q kill
        bindsym $mod+Shift+e exit
        bindsym $mod+Left focus left
        bindsym $mod+Right focus right
        bindsym $mod+Up focus up
        bindsym $mod+Down focus down

        default_border pixel 2
        font pango:monospace 11
        bar {
            position top
            status_command while date +'%Y-%m-%d %H:%M:%S'; do sleep 1; done
        }
        """
    }

    static func bundledDesktopArchive() -> String? {
        let bundle = Bundle.main
        var path = bundle.path(forResource: "wawona-container-desktop", ofType: nil, inDirectory: "oci")
        if path?.isEmpty != false {
            path = bundle.path(forResource: "wawona-container-desktop", ofType: nil)
        }
        guard let path, !path.isEmpty else { return nil }
        let index = (path as NSString).appendingPathComponent("index.json")
        return FileManager.default.fileExists(atPath: index) ? path : nil
    }

    static func importedDesktopArchive() -> String? {
        var root = ProcessInfo.processInfo.environment["WWN_OCI_ROOT"] ?? ""
        if root.isEmpty {
            root = NSHomeDirectory().appending("/.local/share/wwn-oci")
        }
        let fm = FileManager.default
        let imagesDir = (root as NSString).appendingPathComponent("images")
        guard let catalogFiles = try? fm.contentsOfDirectory(atPath: imagesDir) else { return nil }
        for name in catalogFiles where (name as NSString).pathExtension == "json" {
            let filePath = (imagesDir as NSString).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let ref = (json["reference"] as? String) ?? (json["canonical"] as? String) ?? ""
            guard ref.contains("wawona-container-desktop") else { continue }
            guard let digest = json["manifest_digest"] as? String,
                  digest.hasPrefix("sha256:"), digest.count > 7 else { continue }
            let hex = String(digest.dropFirst(7))
            let layoutDir = (root as NSString)
                .appendingPathComponent("oci-layout")
                .appending("/\(hex)")
            let index = (layoutDir as NSString).appendingPathComponent("index.json")
            if fm.fileExists(atPath: index) { return layoutDir }
        }
        let layouts = (root as NSString).appendingPathComponent("oci-layout")
        if let kids = try? fm.contentsOfDirectory(atPath: layouts), kids.count == 1 {
            let layoutDir = (layouts as NSString).appendingPathComponent(kids[0])
            let index = (layoutDir as NSString).appendingPathComponent("index.json")
            if fm.fileExists(atPath: index) { return layoutDir }
        }
        return nil
    }

    static func desktopArchive() -> String? {
        bundledDesktopArchive() ?? importedDesktopArchive()
    }

    static func nativeRecipeSpec(_ recipe: String) -> [String: String]? {
        let map: [String: [String: String]] = [
            "weston": ["id": "weston", "name": "Weston"],
            "niri": ["id": "niri", "name": "Niri"],
            "weston-terminal": ["id": "weston-terminal", "name": "Weston Terminal"],
            "foot": ["id": "foot", "name": "Foot"],
            "weston-simple-egl": ["id": "weston-simple-egl", "name": "Weston Simple EGL"],
            "weston-simple-shm": ["id": "weston-simple-shm", "name": "Weston Simple SHM"],
            "opengl-cube": ["id": "opengl-cube", "name": "OpenGL Cube"],
            "vkcube": ["id": "vkcube", "name": "Vulkan Cube"],
            "kmscube": ["id": "kmscube", "name": "kmscube"],
        ]
        return map[recipe]
    }

    static func containerRecipeSpec(_ recipe: String) -> [String: String]? {
        switch recipe {
        case "flower", "weston-flower":
            return ["name": "Flower (container)", "entry": "weston-flower", "mem": "2048"]
        case "sway":
            let cfg = swayConfig()
            let b64 = Data(cfg.utf8).base64EncodedString()
            let entry =
                "sh -c 'export WLR_BACKENDS=wayland WLR_RENDERER=pixman "
                + "WLR_LIBINPUT_NO_DEVICES=1 XDG_CONFIG_HOME=/tmp/wawona-xdg; "
                + "mkdir -p \"$XDG_CONFIG_HOME/sway\"; "
                + "echo \(b64) | base64 -d > \"$XDG_CONFIG_HOME/sway/config\"; "
                + "exec sway -c \"$XDG_CONFIG_HOME/sway/config\"'"
            return ["name": "Sway (container)", "entry": entry, "mem": "2048"]
        case "labwc":
            return ["name": "labwc (container)", "entry": "labwc", "mem": "2048"]
        case "plasma", "kwin":
            return [
                "name": "Plasma / KWin (container)",
                "entry": "sh -c 'export QT_QPA_PLATFORM=wayland; exec kwin_wayland --platform wayland'",
                "mem": "4096",
            ]
        case "gnome":
            return [
                "name": "GNOME (container)",
                "entry": "sh -c 'mkdir -p /run/user/0; exec dbus-run-session -- gnome-shell --wayland'",
                "mem": "4096",
            ]
        case "hyprland":
            return [
                "name": "Hyprland (container)",
                "entry": "sh -c 'export WLR_BACKENDS=wayland WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1; exec Hyprland'",
                "mem": "4096",
            ]
        case "weston-container":
            return ["name": "Weston (container)", "entry": "weston --backend=wayland", "mem": "2048"]
        default:
            return nil
        }
    }

    static func containerSettings(for spec: [String: String]) -> [String: Any] {
        var cs: [String: Any] = [
            "entryCommand": spec["entry"] ?? "",
            "containerRef": desktopImageRef,
            "desktopSession": true,
            "memory": spec["mem"] ?? "2048",
            "remove": true,
        ]
        if let archive = desktopArchive() {
            cs["imageArchivePath"] = archive
        }
        return cs
    }
}
#endif
